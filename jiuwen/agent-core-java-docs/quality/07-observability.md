# 可观测性 — agent-core-java 质量评估

> 组: C 运行时质量 | 分: **3/4** | 否决项: 否 | 评估卡: [dims/observability.md](file:///D:/jiuwen/main/yoskills/common/project-analysis/dims/observability.md)

## 评分锚点依据

超过 3 档「结构化日志 + 部分指标 + 无追踪 + 有健康检查」，因已具备完整 OpenTelemetry 分布式追踪；但未达 4 档，因缺健康检查端点、RED/USE 完整指标、告警规则、错误聚合。

## 评估过程

- **信号命中**：无结构化日志 ❌（实际有）、无指标采集 ✅、无分布式追踪 ❌（实际有 OTel）、日志无关联 ID ❌（实际有 trace_id）、无告警 ✅、无错误聚合 ✅、无健康检查端点 ✅
- **Read**：[logback.xml](file:///D:/jiuwen/main/agent-core-java/src/main/resources/logback.xml) PATTERN 注入 trace_id；[DefaultLogger.java:347-349](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/logging/defaults/DefaultLogger.java#L347-L349) MDC.put trace_id
- **Read**：[OtelTracerSetup.java:65-98](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/tracerotel/OtelTracerSetup.java#L65-L98) SdkTracerProvider + OTLP 导出
- **Grep**：`actuator|micrometer|prometheus|HealthIndicator|/health` 在 src 下无命中

## 关键问题（带证据）

1. **结构化日志 + 关联 ID**：[logback.xml:14-17](file:///D:/jiuwen/main/agent-core-java/src/main/resources/logback.xml#L14-L17) CONSOLE/FILE PATTERN 注入 `[%X{trace_id:-N/A}]` 与 `[%X{log_type:-common}]`；[DefaultLogger.java:347-349](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/logging/defaults/DefaultLogger.java#L347-L349) 每次输出前 `MDC.put("trace_id", ...)`；`logEvent`（[L307-339](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/common/logging/defaults/DefaultLogger.java#L307-L339)）事件序列化为 JSON；日志按 run/interface/performance 三类滚动（[logback.xml:28-70](file:///D:/jiuwen/main/agent-core-java/src/main/resources/logback.xml#L28-L70)），100MB/30天/3GB 上限。
2. **分布式追踪（OTel 全链路）**：[OtelTracerSetup.java:65-98](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/tracerotel/OtelTracerSetup.java#L65-L98) 构建 `SdkTracerProvider` + `parentBased(traceIdRatioBased)` 采样 + OTLP gRPC/HTTP 导出；[OtelRail.java:79-125](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/extensions/tracerotel/OtelRail.java#L79-L125) 在 agent/LLM/tool 调用前后创建 root/child span；[ObservabilitySetup.java:86-130](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/agentteams/observability/ObservabilitySetup.java#L86-L130) 团队级 TracerProvider 生命周期与多导出器。
3. **指标/健康/告警/错误聚合缺失**：[CallbackMetrics.java:26-90](file:///D:/jiuwen/main/agent-core-java/src/main/java/com/openjiuwen/core/runner/callback/CallbackMetrics.java#L26-L90) 仅内存 POJO（callCount/totalTime/errorCount），无 Micrometer/Actuator/Prometheus；无 HealthIndicator/`/health`；无 Sentry/Rollbar 错误聚合；无告警规则目录。

## 改进建议

1. 引入 Micrometer + Actuator 暴露 RED 指标（LLM QPS/延迟/错误率、向量库召回延迟）
2. 补 `/health` 与 `/ready` 端点（即便作为库，也应提供 `HealthCheck` 抽象）
3. `CallbackMetrics` 接入 MeterRegistry 以导出 Prometheus
4. 接入 Sentry/类似工具做错误聚合；为 OTel span 补 runbook/告警规则

## 业界对标

- 标杆：Spring Boot actuator（健康/指标）、eladmin 的 logging 模块
- 差距：本项目 OTel 全链路追踪是强项（超 3 档），但缺 actuator 健康端点与 RED 指标
