package com.example.rsidemo;

import com.openjiuwen.rsi.harness_rsi.evaluation_result_analyzer.EvaluationResultAnalyzer;
import com.openjiuwen.rsi.harness_rsi.member_optimizer.ActionExecutor;
import com.openjiuwen.rsi.harness_rsi.member_optimizer.HarnessChangeVerifier;
import com.openjiuwen.rsi.harness_rsi.member_optimizer.MemberOptimizer;
import com.openjiuwen.rsi.harness_rsi.member_optimizer.MemberSelector;
import com.openjiuwen.rsi.harness_rsi.member_optimizer.MechanismAttributor;
import com.openjiuwen.rsi.harness_rsi.member_optimizer.PublishCoordinator;
import com.openjiuwen.rsi.harness_rsi.member_optimizer.RoleAttributor;
import com.openjiuwen.rsi.harness_rsi.single_harness.PromotionPolicy;
import com.openjiuwen.rsi.harness_rsi.single_harness.SingleHarnessIterativeOptimizationOrchestrator;
import com.openjiuwen.rsi.integration.RsiRuntimeImpl;
import com.openjiuwen.spi.rsi.RsiTaskRequest;

/**
 * demo 专用 RSI 运行时：复用 RsiRuntimeImpl 的全部编排/状态机/发布逻辑，
 * 仅重写 createOrchestrator，把两个默认依赖 LLM 的组件替换为脚本化实现：
 * <ul>
 *   <li>评测器 DeepAgentRsiEvaluator（需模型）→ {@link StubEvaluator}（脚本化分数）；</li>
 *   <li>默认 ActionPlanner lambda（需模型）→ {@link ScriptedActionPlanner}（确定性动作）。</li>
 * </ul>
 *
 * <p>其余组件与 RsiRuntimeImpl 默认装配完全一致（EvaluationResultAnalyzer、
 * RoleAttributor("default")、MechanismAttributor、MemberSelector(1)、
 * ActionExecutor(packageRoot)、HarnessChangeVerifier、PublishCoordinator(outputDir)、
 * PromotionPolicy），因此 issue 分析、门禁评估、发布写盘均走真实框架代码。
 */
public final class DemoRsiRuntime extends RsiRuntimeImpl {

    @Override
    protected SingleHarnessIterativeOptimizationOrchestrator createOrchestrator(RsiTaskRequest request) {
        // 评测器：脚本化分数（无模型依赖）
        StubEvaluator evaluator = new StubEvaluator();
        // 低分阈值 0.6，与框架默认一致（DEFAULT_LOW_SCORE_THRESHOLD）
        EvaluationResultAnalyzer analyzer = new EvaluationResultAnalyzer();
        // 动作执行器：worktree 根 = packageRoot（框架默认传 harnessRefsPath，即输入包目录）
        ActionExecutor actionExecutor = new ActionExecutor(request.harnessRefsPath());
        // 发布协调器：产物写入 outputDir（框架默认传 outputDir）
        PublishCoordinator publisher = new PublishCoordinator(request.outputDir());
        // 归因与选择：与默认装配一致（role=default、maxRoles=1）
        RoleAttributor roleAttributor = new RoleAttributor("default");
        MechanismAttributor mechanismAttributor = new MechanismAttributor();
        MemberSelector memberSelector = new MemberSelector(1);
        // 规划器：确定性动作规划（无模型依赖）
        ScriptedActionPlanner planner = ScriptedActionPlanner.instance();
        // 变更校验器：默认装配
        HarnessChangeVerifier verifier = new HarnessChangeVerifier();
        MemberOptimizer optimizer = new MemberOptimizer(
                roleAttributor, mechanismAttributor, memberSelector,
                planner, actionExecutor, verifier, publisher);
        // 门禁：默认两阶段阈值（minImprovement=0.05、nonTargetMaxRegression=0.05）
        PromotionPolicy promotionPolicy = new PromotionPolicy();
        return new SingleHarnessIterativeOptimizationOrchestrator(
                evaluator, analyzer, optimizer, promotionPolicy);
    }
}
