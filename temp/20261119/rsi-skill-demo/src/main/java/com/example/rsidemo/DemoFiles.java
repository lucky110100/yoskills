package com.example.rsidemo;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;

/**
 * demo 运行时产物准备：幂等地重建 dataset.json 与 skill_package/，并清空 output/。
 *
 * <p>内容与仓库中的样例文件保持一致；output 目录与 skill_package 目录严格分离
 * （框架 copyDirectory 对输入目录包含输出目录的场景有包含性防护，故必须分离）。
 */
final class DemoFiles {

    private DemoFiles() {
    }

    /** math-tutor skill 的 harness_config.yaml 初始内容（language=zh，两个 prompt section）。 */
    private static final String HARNESS_CONFIG = """
            # math-tutor skill 初始 harness 配置（待 RSI 改进的薄弱版本）
            name: math-tutor
            description: 面向中小学生的数学辅导 skill，负责解答计算题、代数题与逻辑推理题。
            language: zh
            prompts:
              sections:
                - identity
                - method
            """;

    /** identity section 初始内容。 */
    private static final String IDENTITY_MD = """
            # identity
            你是 math-tutor，一名面向中小学生的数学辅导老师。你的职责是解答学生提出的数学问题，给出正确答案。
            """;

    /** method/arith section 初始内容（计算题已较完整）。 */
    private static final String ARITH_MD = """
            # arith
            解答加减乘除混合运算题的约定：
            - 按运算优先级计算：先乘除后加减，有括号先算括号内。
            - 给出每一步的中间结果，不要直接给最终答案。
            - 得出最终答案后，用一句话复述题目和答案进行核对。
            """;

    /** method/algebra section 初始内容（故意薄弱：仅一句话，无分步变形依据，暗示 c2 低分）。 */
    private static final String ALGEBRA_MD = """
            # algebra
            解代数方程：把未知数移到等号一边，常数移到另一边，然后求解。
            """;

    /** method/logic section 初始内容。 */
    private static final String LOGIC_MD = """
            # logic
            解答逻辑推理题的约定：
            - 先列出题目中的已知条件。
            - 逐步推理，每一步只使用一个已知条件或一个已推出的结论。
            - 推理完成后，回代检查结论是否与所有条件一致。
            """;

    /** dataset.json 初始内容：3 个 case，s1/s2 为待改进目标，s3 为非目标约束。 */
    private static final String DATASET_JSON = """
            {
              "cases": [
                {
                  "case_id": "s1",
                  "query": "计算 48 - 17 + 9 的结果，并给出计算过程。",
                  "expected": "40。过程：48 - 17 = 31，31 + 9 = 40。要求先算减法再算加法，逐步给出中间结果。"
                },
                {
                  "case_id": "s2",
                  "query": "解方程 3x + 6 = 21，写出每一步的变形依据。",
                  "expected": "x = 5。过程：两边同减 6 得 3x = 15，两边同除以 3 得 x = 5。要求分步说明等式性质。"
                },
                {
                  "case_id": "s3",
                  "query": "已知今天是星期三，问再过 10 天是星期几？",
                  "expected": "星期六。10 mod 7 = 3，星期三往后推 3 天是星期六。"
                }
              ]
            }
            """;

    /**
     * 重建 demo 运行时资产：先删除旧 output，再写入 dataset.json 与 skill_package 文件。
     * 重复运行幂等。
     *
     * @param demoRoot        demo 根目录
     * @param datasetPath     dataset.json 输出路径（demo 根下 dataset/ 子目录）
     * @param skillPackageDir skill_package 目录
     * @throws IOException 文件读写失败时抛出
     */
    static void prepareDemoAssets(Path demoRoot, Path datasetPath, Path skillPackageDir) throws IOException {
        Path outputDir = demoRoot.resolve("output");
        deleteRecursively(outputDir);
        Files.createDirectories(datasetPath.toAbsolutePath().getParent());
        writeUtf8(datasetPath, DATASET_JSON);

        // 整目录重建 skill_package：确保重复运行时总是从薄弱基线版本出发（幂等）
        deleteRecursively(skillPackageDir);
        Path sectionsDir = skillPackageDir.resolve("prompt_sections");
        Files.createDirectories(sectionsDir);
        writeUtf8(skillPackageDir.resolve("harness_config.yaml"), HARNESS_CONFIG);
        writeUtf8(sectionsDir.resolve("identity.md"), IDENTITY_MD);
        writeUtf8(sectionsDir.resolve("arith.md"), ARITH_MD);
        writeUtf8(sectionsDir.resolve("algebra.md"), ALGEBRA_MD);
        writeUtf8(sectionsDir.resolve("logic.md"), LOGIC_MD);
    }

    /** 以 UTF-8 写入文本文件（父目录须已存在）。 */
    private static void writeUtf8(Path file, String content) throws IOException {
        Files.writeString(file, content, StandardCharsets.UTF_8);
    }

    /** 递归删除目录或文件；目标不存在时静默返回。 */
    private static void deleteRecursively(Path target) throws IOException {
        if (!Files.exists(target)) {
            return;
        }
        try (var paths = Files.walk(target)) {
            paths.sorted(Comparator.reverseOrder()).forEach(p -> {
                try {
                    Files.deleteIfExists(p);
                } catch (IOException e) {
                    throw new RuntimeException("删除失败: " + p, e);
                }
            });
        }
    }
}
