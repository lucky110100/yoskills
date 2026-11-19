package com.example.rsidemo;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * dataset.json 读取工具：将 {"cases":[{case_id, query, expected}, ...]} 解析为 RsiCase 列表。
 * 用于 demo 启动前的数据集预检，保证进入优化流程前快速失败。
 */
final class DatasetLoader {

    /** dataset.json 顶层结构。 */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static final class Dataset {
        /** case 列表。 */
        public List<RawCase> cases;
    }

    /** dataset.json 单条 case 的原始字段（下划线风格）。 */
    @JsonIgnoreProperties(ignoreUnknown = true)
    public static final class RawCase {
        /** case 唯一标识，如 s1。 */
        public String case_id;
        /** 学生提问内容。 */
        public String query;
        /** 期望回答要点。 */
        public String expected;
    }

    private DatasetLoader() {
    }

    /**
     * 从指定路径读取数据集并转换为 RsiCase 记录。
     *
     * @param datasetFile dataset.json 绝对路径
     * @return 按文件顺序排列的 case 列表
     * @throws IOException 文件不存在或 JSON 结构非法时抛出
     */
    static List<com.openjiuwen.rsi.schema.RsiSchema.RsiCase> load(Path datasetFile) throws IOException {
        if (!Files.isRegularFile(datasetFile)) {
            throw new IOException("dataset.json 不存在: " + datasetFile.toAbsolutePath());
        }
        ObjectMapper mapper = new ObjectMapper();
        Dataset dataset = mapper.readValue(datasetFile.toFile(), Dataset.class);
        if (dataset.cases == null || dataset.cases.isEmpty()) {
            throw new IOException("dataset.json 未包含任何 case: " + datasetFile.toAbsolutePath());
        }
        return dataset.cases.stream()
                .map(raw -> new com.openjiuwen.rsi.schema.RsiSchema.RsiCase(raw.case_id, raw.query, raw.expected))
                .toList();
    }
}
