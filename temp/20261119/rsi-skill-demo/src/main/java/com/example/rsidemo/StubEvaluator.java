package com.example.rsidemo;

import com.openjiuwen.rsi.harness_rsi.evaluator.RsiTeamEvaluator;
import com.openjiuwen.rsi.schema.RsiSchema.RsiCase;
import com.openjiuwen.rsi.schema.RsiSchema.RsiCaseScore;
import com.openjiuwen.rsi.schema.RsiSchema.RsiEvaluationResult;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * 脚本化评测器：模拟 "math-tutor" skill 经 RSI 逐步改进后的评分走势，替代真实 LLM 评测。
 *
 * <p>分数脚本（按 evaluate 调用序号；每个 epoch 开始都会先复评当前包，因此基线会连评两次）：
 * <pre>
 *   call 0  基线评测（冻结包）          s1=0.40  s2=0.30  s3=0.90   均分 0.5333
 *   call 1  epoch0 复评（包未变更）     s1=0.40  s2=0.30  s3=0.90   再次产出 2 个 issue
 *   call 2  epoch0 候选复评（已增强）   s1=0.80  s2=0.70  s3=0.90   门禁接受，均分 0.80
 *   call 3  epoch1 复评（候选未变更）   s1=0.80  s2=0.70  s3=0.90   无 issue → 循环收敛
 * </pre>
 *
 * <p>门禁语义对齐（阈值与框架一致）：
 * <ul>
 *   <li>低分阈值 0.6：call 0/1 中 s1/s2 &lt; 0.6 产 2 个 issue，s3 达标非目标；</li>
 *   <li>目标 case 提升：s1 +0.40、s2 +0.40，均 &gt; minImprovement(0.05)；</li>
 *   <li>非目标 case 退化：s3 变化 0.00 ≤ nonTargetMaxRegression(0.05)；</li>
 *   <li>接受后均分 0.80 &gt; 基线 0.5333，PromotionPolicy 放行发布。</li>
 * </ul>
 *
 * <p>基线 call 的 trace 写入包含 "skill" 关键词的中文现象描述，供 EvaluatorResultAnalyzer
 * 的 suspectSurfaces 依据 trace 关键词猜测待优化的表面（prompt_section）。
 */
public final class StubEvaluator implements RsiTeamEvaluator {

    /** 基线分数（call 0 与 call 1：冻结包未变更）。 */
    private static final Map<String, Double> BASELINE = Map.of("s1", 0.40, "s2", 0.30, "s3", 0.90);

    /** 改进后分数（call 2 起：候选包已按动作增强）。 */
    private static final Map<String, Double> IMPROVED = Map.of("s1", 0.80, "s2", 0.70, "s3", 0.90);

    /** 目标 case 的基线现象描述（trace 含 "skill" 关键词）。 */
    private static final Map<String, String> BASELINE_TRACES = Map.of(
            "s1", "学生答错：期望『40』与实际不符 (skill 提示词缺少分步引导，中间结果跳步)",
            "s2", "学生答错：期望『x = 5』与实际不符 (skill 提示词缺少移项变形依据的分步说明)",
            "s3", "回答正确：10 mod 7 = 3，星期三往后推 3 天是星期六。");

    /** evaluate 调用计数：0/1 = 基线（冻结包），≥2 = 候选包。 */
    private final AtomicInteger callCounter = new AtomicInteger(0);

    /** evalId 序号（随调用自增）。 */
    private final AtomicInteger evalSeq = new AtomicInteger(0);

    @Override
    public RsiEvaluationResult evaluate(String harnessRefsPath, List<RsiCase> cases) throws IOException {
        int callIndex = callCounter.getAndIncrement();
        Map<String, Double> scripted = callIndex >= 2 ? IMPROVED : BASELINE;
        Map<String, RsiCaseScore> scores = new LinkedHashMap<>();
        for (RsiCase c : cases) {
            Double value = scripted.get(c.caseId());
            if (value == null) {
                throw new IOException("数据集 case 未配置脚本分数: " + c.caseId());
            }
            String trace = callIndex >= 2
                    ? "回答正确：" + c.expected()
                    : BASELINE_TRACES.getOrDefault(c.caseId(), "回答正确。");
            scores.put(c.caseId(), new RsiCaseScore(c.caseId(), value, trace));
        }
        String evalId = "eval-" + evalSeq.incrementAndGet();
        System.out.printf("[StubEvaluator] call=%d eval=%s harness=%s 均分=%.4f%n",
                callIndex, evalId, harnessRefsPath,
                scores.values().stream().mapToDouble(RsiCaseScore::score).average().orElse(0.0));
        return new RsiEvaluationResult(evalId, scores);
    }
}
