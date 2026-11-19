package com.example.rsidemo;

import com.openjiuwen.rsi.harness_rsi.member_optimizer.ActionPlanner;
import com.openjiuwen.rsi.schema.RsiSchema.MemberOptimizationAction;
import com.openjiuwen.rsi.schema.RsiSchema.TeamIssue;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 脚本化动作规划器：把评测阶段产出的 TeamIssue 确定性地转换为 prompt 文件修改动作，
 * 模拟 "LLM 规划" 环节，使整个 RSI 闭环在无模型环境下可复现。
 *
 * <p>动作配方与框架默认规划器一致（ActionGroupPolicy 白名单校验通过）：
 * groupId = action-&lt;caseId&gt;、group = prompt、operation = modify、
 * path = prompt_sections/&lt;member&gt;.md（相对 worktree 根）、content = 增强后的提示词。
 */
public final class ScriptedActionPlanner implements ActionPlanner {

    /** issue caseId → 待修改的 prompt 成员文件（不含目录前缀）。 */
    private static final Map<String, String> MEMBER_BY_CASE = Map.of(
            "s1", "arith.md",
            "s2", "algebra.md");

    /** 修改后的增强提示词内容（与 StubEvaluator 的 IMPROVED 版本标记对齐）。 */
    private static final Map<String, String> IMPROVED_CONTENT = Map.of(
            "arith.md", """
                    # arith
                    解答加减乘除混合运算题的约定：
                    - 按运算优先级计算：先乘除后加减，有括号先算括号内。
                    - 必须逐步给出每一步的中间结果，禁止跳步或直接给最终答案。
                    - 每完成一步，用一句话说明该步的运算依据（交换律、结合律或优先级）。
                    - 得出最终答案后，按原步骤顺序复述一遍进行核对，确认每步结果无误。
                    """,
            "algebra.md", """
                    # algebra
                    解一元一次方程的分步约定：
                    - 第一步：观察方程结构，明确未知数项与常数项。
                    - 第二步：利用等式性质 1（两边同加减同一个数），把常数项移到等号一边，并写明"两边同减/加 X"。
                    - 第三步：利用等式性质 2（两边同乘除同一个非零数），把未知数系数化为 1，并写明"两边同除以 X"。
                    - 第四步：把求得的解代入原方程回代验证，确认等式成立。
                    """);

    private ScriptedActionPlanner() {
    }

    /** 供 DemoRsiRuntime 复用的单例。 */
    static ScriptedActionPlanner instance() {
        return Holder.INSTANCE;
    }

    /**
     * 将每个 issue 转换为一个 modify 动作；未知 caseId 跳过（不产生动作）。
     *
     * @param role       当前优化的成员角色（demo 中恒为 default）
     * @param issues     评测分析器产出的低分 issue 列表
     * @param maxActions 单轮动作数上限
     * @return 确定性动作列表（可能为空，空列表表示本轮无可执行动作）
     */
    @Override
    public List<MemberOptimizationAction> plan(String role, List<TeamIssue> issues, int maxActions) {
        List<MemberOptimizationAction> actions = new ArrayList<>();
        if (issues == null) {
            return List.of();
        }
        for (TeamIssue issue : issues) {
            if (actions.size() >= maxActions) {
                break;
            }
            String member = MEMBER_BY_CASE.get(issue.caseId());
            if (member == null) {
                continue;
            }
            actions.add(new MemberOptimizationAction(
                    "action-" + issue.caseId(),
                    "prompt",
                    "modify",
                    "prompt_sections/" + member,
                    IMPROVED_CONTENT.get(member)));
        }
        return List.copyOf(actions);
    }

    /** 惰性初始化单例。 */
    private static final class Holder {
        private static final ScriptedActionPlanner INSTANCE = new ScriptedActionPlanner();
    }
}
