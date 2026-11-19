package com.example.rsidemo;

import com.openjiuwen.spi.rsi.RsiRuntime;
import com.openjiuwen.spi.rsi.RsiRuntimeResolver;
import com.openjiuwen.spi.rsi.RsiScenario;
import com.openjiuwen.spi.rsi.RsiStatus;
import com.openjiuwen.spi.rsi.RsiTaskHandle;
import com.openjiuwen.spi.rsi.RsiTaskRequest;
import com.openjiuwen.spi.rsi.RsiTaskState;

import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Map;
import java.util.Optional;

/**
 * RSI skill 改进 demo 入口。
 *
 * <p>流程：
 * <ol>
 *   <li>准备运行时产物：删除旧 output/，重建 dataset.json 与 skill_package/（幂等）；</li>
 *   <li>SPI 探测并启动 RSI 运行时（异步）执行 HARNESS 场景单 skill 迭代优化；</li>
 *   <li>轮询 getState 到终态（COMPLETED/FAILED/TERMINATED）；</li>
 *   <li>打印 bestScore、bestHarnessRefsPath 及 output 产物文件内容；</li>
 *   <li>断言 bestScore ≈ 0.80 且发布成功，失败时以非零退出码结束。</li>
 * </ol>
 *
 * <p>运行时选择说明：SPI（META-INF/services）发现的是框架自带实现，其默认编排装配了
 * 依赖 LLM 的评测器与动作规划器；demo 在无模型环境下运行，故使用其子类
 * {@link DemoRsiRuntime}——仅把这两个组件替换为脚本化实现，其余装配与框架一致。
 *
 * <p>所有路径基于 demo 根目录解析；运行时工作目录约定为 demo 根目录
 * （user.dir 不可用时回退到约定的固定绝对路径）。
 */
public final class RsiSkillDemo {

    /** 轮询间隔（毫秒）。 */
    private static final long POLL_INTERVAL_MS = 100L;

    /** 轮询总超时（毫秒）。 */
    private static final long POLL_TIMEOUT_MS = Duration.ofSeconds(30).toMillis();

    /** 断言的期望最优均分：(0.8 + 0.7 + 0.9) / 3。 */
    private static final double EXPECTED_BEST_SCORE = 0.80;

    private RsiSkillDemo() {
    }

    public static void main(String[] args) {
        try {
            Path demoRoot = resolveDemoRoot();
            System.out.println("[Demo] 根目录: " + demoRoot.toAbsolutePath());

            Path datasetPath = demoRoot.resolve("dataset").resolve("dataset.json");
            Path skillPackageDir = demoRoot.resolve("skill_package");
            Path outputDir = demoRoot.resolve("output");

            DemoFiles.prepareDemoAssets(demoRoot, datasetPath, skillPackageDir);

            // 数据集预检：进入优化流程前确认 dataset.json 可解析，快速失败
            int caseCount = DatasetLoader.load(datasetPath).size();
            System.out.println("[Demo] 数据集预检通过: " + caseCount + " cases @ " + datasetPath);

            // SPI 探测（信息性）：classpath 含 core-rsi 时经 META-INF/services 发现框架实现
            String spiImpl = RsiRuntimeResolver.find()
                    .map(r -> r.getClass().getName())
                    .orElse("(未发现)");
            System.out.println("[Demo] SPI 探测 RsiRuntime: " + spiImpl);

            // demo 实际运行时：替换 LLM 依赖组件的子类实现
            RsiRuntime runtime = new DemoRsiRuntime();
            System.out.println("[Demo] 实际使用 RsiRuntime: " + runtime.getClass().getName());

            RsiTaskRequest request = new RsiTaskRequest(
                    RsiScenario.HARNESS,
                    "rsi-skill-demo",
                    datasetPath.toAbsolutePath().toString(),
                    skillPackageDir.toAbsolutePath().toString(),
                    outputDir.toAbsolutePath().toString(),
                    Map.of(),
                    2);
            RsiTaskHandle handle = runtime.startOptimization(request);
            System.out.println("[Demo] 任务已启动: taskId=" + handle.taskId() + " status=" + handle.status());

            RsiTaskState finalState = awaitTerminalState(runtime, handle.taskId());
            System.out.println("[Demo] 终态: " + finalState);
            if (finalState.status() != RsiStatus.COMPLETED) {
                System.err.println("[Demo] 任务未成功结束: " + finalState.status()
                        + " error=" + finalState.error());
                System.exit(1);
            }

            System.out.println("[Demo] bestScore = " + finalState.bestScore());
            System.out.println("[Demo] bestHarnessRefsPath = " + finalState.bestHarnessRefsPath());
            runtime.getBestHarnessRefs(handle.taskId())
                    .ifPresent(p -> System.out.println("[Demo] getBestHarnessRefs = " + p));

            printArtifact(outputDir.resolve("published_harness_refs.yaml"));
            printArtifact(outputDir.resolve("single_harness_state.yaml"));

            double best = finalState.bestScore() == null ? Double.NaN : finalState.bestScore();
            if (Math.abs(best - EXPECTED_BEST_SCORE) > 1e-6) {
                System.err.println("[Demo] 断言失败: bestScore 期望 " + EXPECTED_BEST_SCORE
                        + "，实际 " + best);
                System.exit(1);
            }
            System.out.println("[Demo] DONE: RSI skill 改进闭环验证通过 (bestScore=" + best + ")");
        } catch (Exception e) {
            System.err.println("[Demo] 运行异常: " + e.getClass().getName() + ": " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }

    /**
     * 解析 demo 根目录：优先使用当前工作目录（约定为 demo 根目录）；
     * 其不像 demo 根目录（缺少 src）时回退到约定的固定绝对路径。
     */
    private static Path resolveDemoRoot() {
        Path cwd = Path.of("").toAbsolutePath();
        if (Files.isDirectory(cwd.resolve("src"))) {
            return cwd;
        }
        Path fixed = Path.of("D:", "yaodh", "main", "yoskills", "temp", "20261119", "rsi-skill-demo");
        if (Files.isDirectory(fixed)) {
            return fixed;
        }
        return cwd;
    }

    /** 轮询任务状态直到终态或超时；超时视为失败。 */
    private static RsiTaskState awaitTerminalState(RsiRuntime runtime, String taskId) throws InterruptedException {
        long deadline = System.currentTimeMillis() + POLL_TIMEOUT_MS;
        while (System.currentTimeMillis() < deadline) {
            Optional<RsiTaskState> state = runtime.getState(taskId);
            if (state.isPresent()) {
                RsiStatus status = state.get().status();
                System.out.printf("[Demo] 轮询 status=%s iteration=%d bestScore=%s%n",
                        status, state.get().iteration(), state.get().bestScore());
                if (status == RsiStatus.COMPLETED || status == RsiStatus.FAILED
                        || status == RsiStatus.TERMINATED) {
                    return state.get();
                }
            }
            Thread.sleep(POLL_INTERVAL_MS);
        }
        throw new IllegalStateException("轮询超时（30s）未到达终态, taskId=" + taskId);
    }

    /** 打印单个产物文件内容；缺失时输出占位提示，退出码由断言决定。 */
    private static void printArtifact(Path file) {
        System.out.println("[Demo] ---- " + file.getFileName() + " ----");
        try {
            if (Files.isRegularFile(file)) {
                System.out.println(Files.readString(file).stripTrailing());
            } else {
                System.out.println("(未生成)");
            }
        } catch (Exception e) {
            System.out.println("(读取失败: " + e.getMessage() + ")");
        }
    }
}
