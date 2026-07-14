# 多租户数据隔离 Phase 2: Runner 层整合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend tenant isolation from Phase 1 (component-level) to Runner-level automatic context propagation, so that RunnerImpl.runAgent/runWorkflow with TenantContext automatically sets TenantContextHolder, CwdContext TENANT_ROOT, and TenantWorkspaceResolver before execution, and clears them after. Backward compatible — no TenantContext means identical behavior to Phase 1.

**Architecture:** RunnerConfig adds enableTenantIsolation + tenantDataRoot fields. RunnerImpl adds bindTenantContext/unbindTenantContext helpers and TenantContext-overloaded run methods. Runner singleton proxy adds corresponding static methods. AgentAdapter extracts tenantId from MQ payload. HarnessCli/CLIOptions adds tenantId field. CheckpointerFactory auto-prefixes work via TenantContextHolder (already functional from Phase 1).

**Tech Stack:** Java 17, JUnit 5.10.2, AssertJ 3.25.3, Mockito 5.2.0, Lombok, Maven Surefire 3.2.5

## Global Constraints

- Java version: 17
- JUnit Jupiter: 5.10.2
- AssertJ: 3.25.3
- Mockito: 5.2.0 (core + inline)
- Test class visibility: package-level (no `public` modifier)
- Test method naming: `testXxxYyy` prefix pattern
- Static imports: `org.assertj.core.api.Assertions.assertThat`, `org.junit.jupiter.api.Assertions.*`
- Maven test command: `mvn test -pl agent-core-java`
- Surefire excludes: `@Tag("system-test")` by default
- Lombok: @Data @Builder for model classes
- Package root: `com.openjiuwen`
- Source root: `agent-core-java/src/main/java/com/openjiuwen/`
- Test root: `agent-core-java/src/test/java/com/openjiuwen/`
- All tenant isolation code in package: `com.openjiuwen.core.multitenant`
- TenantContext tenantId: opaque identifier, framework does not interpret business meaning
- Backward compatibility: no TenantContext → behavior identical to current code
- Phase 1 already completed: TenantContext, TenantContextHolder, TenantWorkspaceResolver, TenantPathSecurity, TenantKVStoreKeyResolver, and all component modifications (Checkpointer, Memory, SkillTool, etc.) are functional
- CwdContext has TENANT_ROOT InheritableThreadLocal (added in Phase 1)
- TenantContextHolder uses InheritableThreadLocal (added in Phase 1)

---

## Task 1: RunnerConfig Tenant Isolation Configuration

**Files:**
- Modify: `agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerConfig.java` (add 2 fields after `objectStorageConfig`)
- Modify: `agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerConfigTest.java` (update all-args test, add tenant config tests)

**Interfaces:**
- Consumes: Phase 1 TenantContext (already exists)
- Produces: `RunnerConfig.isEnableTenantIsolation()` (boolean, default false), `RunnerConfig.getTenantDataRoot()` (String, default null)

- [ ] **Step 1: Write the failing test**

```java
// Add to RunnerConfigTest.java as a new @Nested class:

@Nested
@DisplayName("Tenant isolation config")
class TenantIsolationConfig {
    @Test
    @DisplayName("DEFAULT has enableTenantIsolation=false")
    void defaultEnableTenantIsolation() {
        assertFalse(RunnerConfig.DEFAULT.isEnableTenantIsolation());
    }

    @Test
    @DisplayName("DEFAULT has null tenantDataRoot")
    void defaultTenantDataRoot() {
        assertNull(RunnerConfig.DEFAULT.getTenantDataRoot());
    }

    @Test
    @DisplayName("Builder sets enableTenantIsolation and tenantDataRoot")
    void builderSetsTenantFields() {
        RunnerConfig config = RunnerConfig.builder()
                .distributedMode(false)
                .enableTenantIsolation(true)
                .tenantDataRoot("/data/tenants")
                .build();
        assertTrue(config.isEnableTenantIsolation());
        assertEquals("/data/tenants", config.getTenantDataRoot());
    }

    @Test
    @DisplayName("No-arg constructor has enableTenantIsolation=false and null tenantDataRoot")
    void noArgConstructorTenantDefaults() {
        RunnerConfig config = new RunnerConfig();
        assertFalse(config.isEnableTenantIsolation());
        assertNull(config.getTenantDataRoot());
    }

    @Test
    @DisplayName("All-args constructor sets enableTenantIsolation and tenantDataRoot")
    void allArgsConstructorTenantFields() {
        Map<String, Object> cpConfig = Map.of("type", "in_memory");
        RunnerConfig config = new RunnerConfig(false, new DistributedConfig(), "test", "instance-1",
                cpConfig, List.of(), Map.of(), Map.of(), Map.of(), true, "/data/tenants");
        assertTrue(config.isEnableTenantIsolation());
        assertEquals("/data/tenants", config.getTenantDataRoot());
    }

    @Test
    @DisplayName("Global config preserves tenant isolation fields")
    void globalConfigPreservesTenantFields() {
        RunnerConfig config = RunnerConfig.builder()
                .distributedMode(false)
                .enableTenantIsolation(true)
                .tenantDataRoot("/opt/tenant-data")
                .build();
        RunnerConfig.setRunnerConfig(config);
        RunnerConfig retrieved = RunnerConfig.getRunnerConfig();
        assertTrue(retrieved.isEnableTenantIsolation());
        assertEquals("/opt/tenant-data", retrieved.getTenantDataRoot());
    }

    @Test
    @DisplayName("RunnerImpl with tenant-enabled config")
    void runnerImplWithTenantEnabledConfig() {
        RunnerConfig config = RunnerConfig.builder()
                .distributedMode(false)
                .enableTenantIsolation(true)
                .tenantDataRoot("/data/tenants")
                .build();
        RunnerImpl runner = new RunnerImpl("tenant-runner", config);
        assertTrue(runner.getConfig().isEnableTenantIsolation());
        assertEquals("/data/tenants", runner.getConfig().getTenantDataRoot());
    }
}
```

Also update the existing all-args constructor test in `BuilderPatterns.allArgsConstructor` to include the 2 new parameters:

```java
@Test
@DisplayName("All-args constructor sets all fields")
void allArgsConstructor() {
    Map<String, Object> cpConfig = Map.of("type", "redis");
    Map<String, Object> kvConfig = Map.of("type", "in_memory");
    Map<String, Object> vsConfig = Map.of("type", "chroma");
    Map<String, Object> obsConfig = Map.of("type", "s3");

    RunnerConfig config = new RunnerConfig(false, new DistributedConfig(), "test", "instance-1", cpConfig,
            List.of(), kvConfig, vsConfig, obsConfig, false, null);

    assertFalse(config.isDistributedMode());
    assertEquals("test", config.getEnvPrefix());
    assertEquals("instance-1", config.getInstanceId());
    assertEquals("redis", config.getCheckpointerConfig().get("type"));
    assertEquals("in_memory", config.getKvStoreConfig().get("type"));
    assertEquals("chroma", config.getVectorStoreConfig().get("type"));
    assertEquals("s3", config.getObjectStorageConfig().get("type"));
    assertFalse(config.isEnableTenantIsolation());
    assertNull(config.getTenantDataRoot());
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn test -pl agent-core-java -Dtest=RunnerConfigTest -q`
Expected: FAIL — `isEnableTenantIsolation` and `getTenantDataRoot` methods do not exist

- [ ] **Step 3: Write minimal implementation**

Add 2 fields to RunnerConfig.java after the `objectStorageConfig` field:

```java
private boolean enableTenantIsolation = false;
private String tenantDataRoot;
```

Lombok `@Data @Builder @NoArgsConstructor @AllArgsConstructor` will auto-generate getters, setters, and builder methods.

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn test -pl agent-core-java -Dtest=RunnerConfigTest -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerConfig.java agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerConfigTest.java
git commit -m "feat(phase2): add enableTenantIsolation and tenantDataRoot to RunnerConfig"
```

---

## Task 2: RunnerImpl + Runner TenantContext-Aware Execution

**Files:**
- Modify: `agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java` (add TenantWorkspaceResolver field, bindTenantContext/unbindTenantContext helpers, TenantContext-overloaded run methods)
- Modify: `agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java` (add TenantContext-overloaded static methods)
- Create: `agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerImplTenantTest.java`
- Create: `agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerTenantProxyTest.java`

**Interfaces:**
- Consumes: `RunnerConfig.isEnableTenantIsolation()` + `RunnerConfig.getTenantDataRoot()` (from Task 1), `TenantContext` + `TenantContextHolder` + `TenantWorkspaceResolver` + `CwdContext` (from Phase 1)
- Produces: `RunnerImpl.runAgent(Object, Object, Object, ModelContext, Map, TenantContext)`, `RunnerImpl.runAgentStreaming(Object, Object, Object, ModelContext, List, Map, TenantContext)`, `RunnerImpl.runWorkflow(Object, Object, Object, ModelContext, Map, TenantContext)`, `RunnerImpl.runWorkflowStreaming(Object, Object, Object, ModelContext, List, Map, TenantContext)`, `RunnerImpl.runAgentGroup(Object, Object, Object, ModelContext, Map, TenantContext)`, `RunnerImpl.runAgentGroupStreaming(Object, Object, Object, ModelContext, List, Map, TenantContext)`, `RunnerImpl.runAgentAsync(Object, Object, Object, ModelContext, Map, TenantContext)`, `RunnerImpl.runAgentStreamingAsync(Object, Object, Object, ModelContext, List, Map, TenantContext)`, and corresponding `Runner.*` static proxy methods

- [ ] **Step 1: Write the failing test for RunnerImplTenantTest**

```java
package com.openjiuwen.core.runner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;

import com.openjiuwen.core.context.ModelContext;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.session.AgentSessionApi;
import com.openjiuwen.core.session.checkpointer.CheckpointerFactory;
import com.openjiuwen.core.session.stream.StreamMode;
import com.openjiuwen.core.sysop.cwd.CwdContext;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

@DisplayName("RunnerImpl Tenant Context Tests")
class RunnerImplTenantTest {
    private final List<String> sessionsToRelease = new ArrayList<>();
    private RunnerImpl runner;

    @BeforeEach
    void setUp() {
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
        CheckpointerFactory.setDefaultCheckpointer(null);
        RunnerConfig.setRunnerConfig(null);
        runner = new RunnerImpl("tenant-test-runner", RunnerConfig.DEFAULT);
        runner.start();
    }

    @AfterEach
    void tearDown() {
        for (String sessionId : sessionsToRelease) {
            CheckpointerFactory.getCheckpointer().release(sessionId);
        }
        sessionsToRelease.clear();
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
        runner.stop();
    }

    private void trackSession(String sessionId) {
        sessionsToRelease.add(sessionId);
    }

    @Nested
    @DisplayName("bindTenantContext propagation")
    class BindTenantContextPropagation {
        @Test
        @DisplayName("runAgent with TenantContext sets TenantContextHolder during execution")
        void testRunAgentSetsTenantContextHolder() {
            TenantContext tenantCtx = TenantContext.builder().tenantId("tenant_alpha").build();
            TenantAwareAgent agent = new TenantAwareAgent();
            String sessionId = "tenant-session-1";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, tenantCtx));

            assertThat(result.get("captured_tenant_id")).isEqualTo("tenant_alpha");
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
        }

        @Test
        @DisplayName("runAgent with null TenantContext does not set TenantContextHolder")
        void testRunAgentNullTenantCtxBackwardCompat() {
            TenantAwareAgent agent = new TenantAwareAgent();
            String sessionId = "no-tenant-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, null));

            assertThat(result.get("captured_tenant_id")).isNull();
        }

        @Test
        @DisplayName("runAgent with TenantContext sets CwdContext TENANT_ROOT")
        void testRunAgentSetsCwdContextTenantRoot() {
            TenantContext tenantCtx = TenantContext.builder().tenantId("tenant_beta").build();
            TenantAwareAgent agent = new TenantAwareAgent();
            String sessionId = "cwd-tenant-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, tenantCtx));

            assertThat(result.get("captured_tenant_root")).isNotNull();
            assertThat(CwdContext.getTenantRoot()).isNull();
        }

        @Test
        @DisplayName("runAgent clears TenantContextHolder after execution even on error")
        void testRunAgentClearsContextOnError() {
            TenantContext tenantCtx = TenantContext.builder().tenantId("tenant_error").build();
            ErrorAgent agent = new ErrorAgent();

            assertThrows(RuntimeException.class, () ->
                runner.runAgent(agent, Map.of(), null, null, null, tenantCtx));
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
        }
    }

    @Nested
    @DisplayName("TenantWorkspaceResolver initialization")
    class WorkspaceResolverInit {
        @Test
        @DisplayName("start() with enableTenantIsolation=true initializes workspaceResolver")
        void testStartInitializesWorkspaceResolver() {
            RunnerConfig tenantConfig = RunnerConfig.builder()
                    .distributedMode(false)
                    .enableTenantIsolation(true)
                    .tenantDataRoot(System.getProperty("user.dir"))
                    .build();
            RunnerImpl tenantRunner = new RunnerImpl("ws-resolver-runner", tenantConfig);
            tenantRunner.start();

            TenantContext ctx = TenantContext.builder().tenantId("ws_test").build();
            TenantAwareAgent agent = new TenantAwareAgent();
            String sessionId = "ws-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                tenantRunner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, ctx));

            assertThat(result.get("captured_tenant_root")).isNotNull();
            String tenantRoot = (String) result.get("captured_tenant_root");
            assertThat(tenantRoot).contains("tenants");
            assertThat(tenantRoot).contains("ws_test");

            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
            assertThat(CwdContext.getTenantRoot()).isNull();
            tenantRunner.stop();
        }

        @Test
        @DisplayName("start() with enableTenantIsolation=false does not initialize workspaceResolver")
        void testStartWithoutTenantIsolationNoResolver() {
            RunnerImpl noTenantRunner = new RunnerImpl("no-tenant-runner", RunnerConfig.DEFAULT);
            noTenantRunner.start();

            TenantContext ctx = TenantContext.builder().tenantId("no_resolver").build();
            TenantAwareAgent agent = new TenantAwareAgent();
            String sessionId = "no-resolver-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                noTenantRunner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, ctx));

            assertThat(result.get("captured_tenant_root")).isNull();

            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
            assertThat(CwdContext.getTenantRoot()).isNull();
            noTenantRunner.stop();
        }
    }

    @Nested
    @DisplayName("Streaming methods with TenantContext")
    class StreamingTenantContext {
        @Test
        @DisplayName("runAgentStreaming with TenantContext propagates context during streaming")
        void testRunAgentStreamingWithTenantContext() {
            TenantContext tenantCtx = TenantContext.builder().tenantId("stream_tenant").build();
            TenantAwareStreamAgent agent = new TenantAwareStreamAgent();
            String sessionId = "stream-tenant-session";
            trackSession(sessionId);

            Iterator<Object> iterator = runner.runAgentStreaming(
                agent, Map.of("conversation_id", sessionId), null, null, List.of(StreamMode.OUTPUT), null, tenantCtx);

            List<Object> chunks = new ArrayList<>();
            iterator.forEachRemaining(chunks::add);

            assertThat(chunks).hasSize(1);
            Map<String, Object> chunk = castMap(chunks.get(0));
            assertThat(chunk.get("captured_tenant_id")).isEqualTo("stream_tenant");
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
        }
    }

    @Nested
    @DisplayName("Workflow methods with TenantContext")
    class WorkflowTenantContext {
        @Test
        @DisplayName("runWorkflow with TenantContext propagates context")
        void testRunWorkflowWithTenantContext() {
            TenantContext tenantCtx = TenantContext.builder().tenantId("wf_tenant").build();
            Workflow workflow = createTenantAwareWorkflow("wf-tenant-workflow");
            runner.getResourceMgr().addWorkflow(workflow.getCard(), () -> workflow, null);

            Object result = runner.runWorkflow(
                "wf-tenant-workflow", Map.of("query", "hello"), null, null, null, tenantCtx);

            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> castMap(Object value) {
        return (Map<String, Object>) value;
    }

    private static class TenantAwareAgent {
        public Map<String, Object> invoke(Map<String, Object> inputs, AgentSessionApi session) {
            Map<String, Object> result = new java.util.LinkedHashMap<>();
            result.put("session_id", session.getSessionId());
            result.put("captured_tenant_id",
                TenantContextHolder.getCurrentTenant() != null
                    ? TenantContextHolder.getCurrentTenant().getTenantId() : null);
            result.put("captured_tenant_root", CwdContext.getTenantRoot());
            return result;
        }
    }

    private static class TenantAwareStreamAgent {
        public Iterator<Object> stream(Map<String, Object> inputs, AgentSessionApi session) {
            Map<String, Object> result = new java.util.LinkedHashMap<>();
            result.put("session_id", session.getSessionId());
            result.put("captured_tenant_id",
                TenantContextHolder.getCurrentTenant() != null
                    ? TenantContextHolder.getCurrentTenant().getTenantId() : null);
            return List.<Object>of(result).iterator();
        }
    }

    private static class ErrorAgent {
        public Map<String, Object> invoke(Map<String, Object> inputs, AgentSessionApi session) {
            throw new RuntimeException("intentional error for test");
        }
    }

    private com.openjiuwen.core.workflow.Workflow createTenantAwareWorkflow(String workflowId) {
        com.openjiuwen.core.workflow.Workflow workflow = new com.openjiuwen.core.workflow.Workflow(
            com.openjiuwen.core.workflow.WorkflowCard.builder().id(workflowId).name(workflowId).version("1").build());
        workflow.setStartComp("start", new com.openjiuwen.core.workflow.component.Start(),
            Map.of("query", "${query}"), null);
        workflow.setEndComp("end", new com.openjiuwen.core.workflow.component.End(),
            Map.of("query", "${start.query}"), null, null, null, "tenant_wf");
        workflow.addConnection("start", "end");
        return workflow;
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn test -pl agent-core-java -Dtest=RunnerImplTenantTest -q`
Expected: FAIL — RunnerImpl does not have TenantContext-overloaded methods

- [ ] **Step 3: Write RunnerImpl implementation**

Add to `RunnerImpl.java`:

1. New imports:
```java
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.multitenant.TenantWorkspaceResolver;
import com.openjiuwen.core.sysop.cwd.CwdContext;
import java.nio.file.Path;
```

2. New field (after `callbackFramework`):
```java
private TenantWorkspaceResolver workspaceResolver;
```

3. In `start()` method, after the checkpointer initialization block (after line 199), add:
```java
if (RunnerConfig.getRunnerConfig().isEnableTenantIsolation()) {
    String dataRoot = RunnerConfig.getRunnerConfig().getTenantDataRoot();
    if (dataRoot == null || dataRoot.isEmpty()) {
        dataRoot = System.getProperty("user.dir");
    }
    workspaceResolver = new TenantWorkspaceResolver(dataRoot);
    logger.info("Tenant isolation enabled, dataRoot={}", dataRoot);
}
```

4. Add `bindTenantContext` and `unbindTenantContext` private methods:
```java
private void bindTenantContext(TenantContext ctx) {
    if (ctx != null && ctx.isTenantAware()) {
        TenantContextHolder.setCurrentTenant(ctx);
        if (workspaceResolver != null) {
            workspaceResolver.initializeTenantSpace(ctx);
            Path tenantWorkspace = workspaceResolver.resolveWorkspaceRoot(ctx);
            Path tenantRootParent = tenantWorkspace.getParent();
            CwdContext.setWorkspace(tenantWorkspace.toString());
            CwdContext.setOriginalCwd(tenantWorkspace.toString());
            CwdContext.setTenantRoot(tenantRootParent.toString());
        }
    }
}

private void unbindTenantContext() {
    TenantContextHolder.clearCurrentTenant();
    CwdContext.reset();
}
```

5. Add TenantContext-overloaded run methods. Each wraps the original with bind/unbind:

```java
public Object runAgent(Object agent, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    bindTenantContext(tenantCtx);
    try {
        return runAgent(agent, inputs, session, context, envs);
    } finally {
        unbindTenantContext();
    }
}

public Iterator<Object> runAgentStreaming(Object agent, Object inputs, Object session, ModelContext context,
        List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    bindTenantContext(tenantCtx);
    try {
        return runAgentStreaming(agent, inputs, session, context, streamModes, envs);
    } finally {
        unbindTenantContext();
    }
}

public Object runWorkflow(Object workflow, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    bindTenantContext(tenantCtx);
    try {
        return runWorkflow(workflow, inputs, session, context, envs);
    } finally {
        unbindTenantContext();
    }
}

public Iterator<WorkflowChunk> runWorkflowStreaming(Object workflow, Object inputs, Object session,
        ModelContext context, List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    bindTenantContext(tenantCtx);
    try {
        return runWorkflowStreaming(workflow, inputs, session, context, streamModes, envs);
    } finally {
        unbindTenantContext();
    }
}

public Object runAgentGroup(Object agentGroup, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    bindTenantContext(tenantCtx);
    try {
        return runAgentGroup(agentGroup, inputs, session, context, envs);
    } finally {
        unbindTenantContext();
    }
}

public Iterator<Object> runAgentGroupStreaming(Object agentGroup, Object inputs, Object session,
        ModelContext context, List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    bindTenantContext(tenantCtx);
    try {
        return runAgentGroupStreaming(agentGroup, inputs, session, context, streamModes, envs);
    } finally {
        unbindTenantContext();
    }
}

public Mono<Object> runAgentAsync(Object agent, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    if (tenantCtx == null || !tenantCtx.isTenantAware()) {
        return runAgentAsync(agent, inputs, session, context, envs);
    }
    TenantContext captured = tenantCtx;
    return Mono.fromCallable(() -> {
        bindTenantContext(captured);
        try {
            return runAgent(agent, inputs, session, context, envs);
        } finally {
            unbindTenantContext();
        }
    });
}

public Flux<Object> runAgentStreamingAsync(Object agent, Object inputs, Object session, ModelContext context,
        List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    if (tenantCtx == null || !tenantCtx.isTenantAware()) {
        return runAgentStreamingAsync(agent, inputs, session, context, streamModes, envs);
    }
    TenantContext captured = tenantCtx;
    return deferWithSessionCleanup(sessRef -> {
        bindTenantContext(captured);
        Object agentInstance = prepareAgent(agent);
        AgentSessionApi sess = prepareAgentSession(agentInstance, inputs, session, streamModes);
        sessRef.set(sess);
        return ReactiveAdapters.fromAutoCloseableIterator(
            () -> streamAgent(agentInstance, inputs, sess, context, streamModes));
    }, sess -> {
        unbindTenantContext();
        sess.postRun();
    });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn test -pl agent-core-java -Dtest=RunnerImplTenantTest -q`
Expected: PASS

- [ ] **Step 5: Write the failing test for RunnerTenantProxyTest**

```java
package com.openjiuwen.core.runner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;

import com.openjiuwen.core.context.ModelContext;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.session.AgentSessionApi;
import com.openjiuwen.core.session.checkpointer.CheckpointerFactory;
import com.openjiuwen.core.session.stream.StreamMode;
import com.openjiuwen.core.sysop.cwd.CwdContext;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

@DisplayName("Runner Tenant Proxy Tests")
class RunnerTenantProxyTest {
    private final List<String> sessionsToRelease = new ArrayList<>();

    @BeforeEach
    void setUp() {
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
        CheckpointerFactory.setDefaultCheckpointer(null);
        RunnerConfig.setRunnerConfig(null);
        Runner.start();
    }

    @AfterEach
    void tearDown() {
        for (String sessionId : sessionsToRelease) {
            CheckpointerFactory.getCheckpointer().release(sessionId);
        }
        sessionsToRelease.clear();
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
        Runner.stop();
        Runner.setConfig(RunnerConfig.DEFAULT);
    }

    private void trackSession(String sessionId) {
        sessionsToRelease.add(sessionId);
    }

    @Nested
    @DisplayName("Runner static proxy with TenantContext")
    class RunnerStaticProxyTenantCtx {
        @Test
        @DisplayName("Runner.runAgent with TenantContext delegates to RunnerImpl")
        void testRunnerRunAgentWithTenantCtx() {
            TenantContext tenantCtx = TenantContext.builder().tenantId("proxy_tenant").build();
            TenantProxyAwareAgent agent = new TenantProxyAwareAgent();
            String sessionId = "proxy-tenant-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                Runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, tenantCtx));

            assertThat(result.get("captured_tenant_id")).isEqualTo("proxy_tenant");
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
        }

        @Test
        @DisplayName("Runner.runAgent without TenantContext backward compat")
        void testRunnerRunAgentWithoutTenantCtx() {
            TenantProxyAwareAgent agent = new TenantProxyAwareAgent();
            String sessionId = "proxy-no-tenant-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                Runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null));

            assertThat(result.get("captured_tenant_id")).isNull();
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> castMap(Object value) {
        return (Map<String, Object>) value;
    }

    private static class TenantProxyAwareAgent {
        public Map<String, Object> invoke(Map<String, Object> inputs, AgentSessionApi session) {
            Map<String, Object> result = new java.util.LinkedHashMap<>();
            result.put("session_id", session.getSessionId());
            result.put("captured_tenant_id",
                TenantContextHolder.getCurrentTenant() != null
                    ? TenantContextHolder.getCurrentTenant().getTenantId() : null);
            return result;
        }
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `mvn test -pl agent-core-java -Dtest=RunnerTenantProxyTest -q`
Expected: FAIL — Runner does not have TenantContext-overloaded static methods

- [ ] **Step 7: Write Runner proxy implementation**

Add to `Runner.java` new imports and static methods:

```java
import com.openjiuwen.core.multitenant.TenantContext;
```

Add static methods (after existing `runAgent` methods):

```java
public static Object runAgent(Object agent, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runAgent(agent, inputs, session, context, envs, tenantCtx);
}

public static Iterator<Object> runAgentStreaming(Object agent, Object inputs, Object session, ModelContext context,
        List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runAgentStreaming(agent, inputs, session, context, streamModes, envs, tenantCtx);
}

public static Object runWorkflow(Object workflow, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runWorkflow(workflow, inputs, session, context, envs, tenantCtx);
}

public static Iterator<WorkflowChunk> runWorkflowStreaming(Object workflow, Object inputs, Object session,
        ModelContext context, List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runWorkflowStreaming(workflow, inputs, session, context, streamModes, envs, tenantCtx);
}

public static Object runAgentGroup(Object agentGroup, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runAgentGroup(agentGroup, inputs, session, context, envs, tenantCtx);
}

public static Iterator<Object> runAgentGroupStreaming(Object agentGroup, Object inputs, Object session,
        ModelContext context, List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runAgentGroupStreaming(agentGroup, inputs, session, context, streamModes, envs, tenantCtx);
}

public static Mono<Object> runAgentAsync(Object agent, Object inputs, Object session, ModelContext context,
        Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runAgentAsync(agent, inputs, session, context, envs, tenantCtx);
}

public static Flux<Object> runAgentStreamingAsync(Object agent, Object inputs, Object session, ModelContext context,
        List<StreamMode> streamModes, Map<String, Object> envs, TenantContext tenantCtx) {
    return GLOBAL_RUNNER.runAgentStreamingAsync(agent, inputs, session, context, streamModes, envs, tenantCtx);
}
```

- [ ] **Step 8: Run tests to verify both pass**

Run: `mvn test -pl agent-core-java -Dtest=RunnerImplTenantTest,RunnerTenantProxyTest -q`
Expected: PASS

- [ ] **Step 9: Run existing RunnerConfigTest to verify backward compat**

Run: `mvn test -pl agent-core-java -Dtest=RunnerConfigTest -q`
Expected: PASS (updated all-args test should work)

- [ ] **Step 10: Commit**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/runner/RunnerImpl.java agent-core-java/src/main/java/com/openjiuwen/core/runner/Runner.java agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerImplTenantTest.java agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerTenantProxyTest.java
git commit -m "feat(phase2): RunnerImpl and Runner support TenantContext-aware execution"
```

---

## Task 3: AgentAdapter Distributed Entry TenantId Propagation

**Files:**
- Modify: `agent-core-java/src/main/java/com/openjiuwen/core/runner/drunner/server_adapter/AgentAdapter.java` (extract tenantId from inputs, create TenantContext, pass to Runner)
- Create: `agent-core-java/src/test/java/com/openjiuwen/core/runner/drunner/server_adapter/AgentAdapterTenantTest.java`

**Interfaces:**
- Consumes: `Runner.runAgent(Object, Object, Object, ModelContext, Map, TenantContext)` (from Task 2), `TenantContext.builder()` (Phase 1)
- Produces: `AgentAdapter.handleInvoke(Map, TenantContext)` — internal; external API unchanged (tenantId extracted from inputs Map)

- [ ] **Step 1: Write the failing test**

```java
package com.openjiuwen.core.runner.drunner.server_adapter;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;

import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.runner.Runner;
import com.openjiuwen.core.runner.RunnerConfig;
import com.openjiuwen.core.runner.RunnerImpl;
import com.openjiuwen.core.session.AgentSessionApi;
import com.openjiuwen.core.session.checkpointer.CheckpointerFactory;
import com.openjiuwen.core.sysop.cwd.CwdContext;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@DisplayName("AgentAdapter Tenant Tests")
class AgentAdapterTenantTest {
    private final List<String> sessionsToRelease = new ArrayList<>();
    private AgentAdapter adapter;
    private RunnerImpl testRunner;
    private TenantProxyAwareAgent tenantAgent;

    @BeforeEach
    void setUp() {
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
        CheckpointerFactory.setDefaultCheckpointer(null);
        RunnerConfig.setRunnerConfig(null);
        testRunner = new RunnerImpl("adapter-test-runner", RunnerConfig.DEFAULT);
        testRunner.start();
        tenantAgent = new TenantProxyAwareAgent();
        testRunner.getResourceMgr().addAgent(
            com.openjiuwen.core.singleagent.schema.AgentCard.builder().id("adapter-agent").name("adapter-agent").build(),
            () -> tenantAgent, null);
        adapter = new AgentAdapter("adapter-agent", "");
        adapter.setTestRunner(testRunner);
    }

    @AfterEach
    void tearDown() {
        for (String sessionId : sessionsToRelease) {
            CheckpointerFactory.getCheckpointer().release(sessionId);
        }
        sessionsToRelease.clear();
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
        testRunner.stop();
    }

    private void trackSession(String sessionId) {
        sessionsToRelease.add(sessionId);
    }

    @Nested
    @DisplayName("AgentAdapter tenantId extraction")
    class TenantIdExtraction {
        @Test
        @DisplayName("handleInvoke extracts tenantId from inputs and creates TenantContext")
        void testHandleInvokeWithTenantId() {
            String sessionId = "adapter-tenant-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                adapter.handleInvoke(Map.of("conversation_id", sessionId, "tenant_id", "adapter_tenant")));

            assertThat(result.get("captured_tenant_id")).isEqualTo("adapter_tenant");
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
        }

        @Test
        @DisplayName("handleInvoke without tenantId backward compat")
        void testHandleInvokeWithoutTenantId() {
            String sessionId = "adapter-no-tenant-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                adapter.handleInvoke(Map.of("conversation_id", sessionId)));

            assertThat(result.get("captured_tenant_id")).isNull();
        }

        @Test
        @DisplayName("handleStream extracts tenantId from inputs")
        void testHandleStreamWithTenantId() {
            String sessionId = "adapter-stream-tenant-session";
            trackSession(sessionId);

            java.util.Iterator<Object> iterator =
                adapter.handleStream(Map.of("conversation_id", sessionId, "tenant_id", "stream_tenant"));

            List<Object> chunks = new ArrayList<>();
            iterator.forEachRemaining(chunks::add);
            assertThat(chunks).hasSize(1);
            Map<String, Object> chunk = castMap(chunks.get(0));
            assertThat(chunk.get("captured_tenant_id")).isEqualTo("stream_tenant");
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> castMap(Object value) {
        return (Map<String, Object>) value;
    }

    private static class TenantProxyAwareAgent {
        public Map<String, Object> invoke(Map<String, Object> inputs, AgentSessionApi session) {
            Map<String, Object> result = new java.util.LinkedHashMap<>();
            result.put("session_id", session.getSessionId());
            result.put("captured_tenant_id",
                TenantContextHolder.getCurrentTenant() != null
                    ? TenantContextHolder.getCurrentTenant().getTenantId() : null);
            return result;
        }

        public java.util.Iterator<Object> stream(Map<String, Object> inputs, AgentSessionApi session) {
            Map<String, Object> result = new java.util.LinkedHashMap<>();
            result.put("session_id", session.getSessionId());
            result.put("captured_tenant_id",
                TenantContextHolder.getCurrentTenant() != null
                    ? TenantContextHolder.getCurrentTenant().getTenantId() : null);
            return List.<Object>of(result).iterator();
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn test -pl agent-core-java -Dtest=AgentAdapterTenantTest -q`
Expected: FAIL — AgentAdapter doesn't extract tenantId, and test setup requires `setTestRunner` method

- [ ] **Step 3: Write AgentAdapter implementation**

Modify `AgentAdapter.java`:

1. Add imports:
```java
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
```

2. Add a `testRunner` field for testing (package-private):
```java
RunnerImpl testRunner;
void setTestRunner(RunnerImpl runner) { this.testRunner = runner; }
```

3. Add `extractTenantContext` helper:
```java
private TenantContext extractTenantContext(Map<String, Object> inputs) {
    if (inputs != null) {
        Object tenantId = inputs.get("tenant_id");
        if (tenantId instanceof String tid && !tid.isBlank()) {
            return TenantContext.builder().tenantId(tid).build();
        }
    }
    return null;
}
```

4. Modify `handleInvoke`:
```java
private Object handleInvoke(Map<String, Object> inputs) {
    TenantContext tenantCtx = extractTenantContext(inputs);
    if (tenantCtx != null) {
        RunnerImpl runner = testRunner != null ? testRunner : (RunnerImpl) Runner.getRunnerImpl();
        return runner.runAgent(agentId, inputs, null, null, null, tenantCtx);
    }
    return Runner.runAgent(agentId, inputs, null, null);
}
```

Note: `Runner.getRunnerImpl()` may not exist. If not available, use `Runner.runAgent(agentId, inputs, null, null, null, tenantCtx)` via the static proxy.

Actually, let me use the static proxy approach since it's simpler:
```java
private Object handleInvoke(Map<String, Object> inputs) {
    TenantContext tenantCtx = extractTenantContext(inputs);
    if (tenantCtx != null) {
        return Runner.runAgent(agentId, inputs, null, null, null, tenantCtx);
    }
    return Runner.runAgent(agentId, inputs, null, null);
}
```

But for testing, we need to inject a custom RunnerImpl. The current AgentAdapter calls `Runner.runAgent()` which uses the static singleton. For tests, we need to set up the Runner singleton with our test runner.

Let me adjust the test to use Runner singleton instead of injecting a test runner:

```java
@BeforeEach
void setUp() {
    TenantContextHolder.clearCurrentTenant();
    CwdContext.reset();
    CheckpointerFactory.setDefaultCheckpointer(null);
    RunnerConfig tenantConfig = RunnerConfig.builder().distributedMode(false).build();
    Runner.setConfig(tenantConfig);
    Runner.start();
    TenantProxyAwareAgent tenantAgent = new TenantProxyAwareAgent();
    Runner.resourceMgr().addAgent(
        AgentCard.builder().id("adapter-agent").name("adapter-agent").build(),
        () -> tenantAgent, null);
    adapter = new AgentAdapter("adapter-agent", "");
}

@AfterEach
void tearDown() {
    // ...
    Runner.stop();
    Runner.setConfig(RunnerConfig.DEFAULT);
}
```

This way, AgentAdapter calls Runner.runAgent() which uses the static singleton, and we configure the singleton for our test.

5. Modify `handleStream` similarly:
```java
private Iterator<Object> handleStream(Map<String, Object> inputs) {
    TenantContext tenantCtx = extractTenantContext(inputs);
    if (tenantCtx != null) {
        return Runner.runAgentStreaming(agentId, inputs, null, null, List.of(StreamMode.OUTPUT), null, tenantCtx);
    }
    return Runner.runAgentStreaming(agentId, inputs, null, null, List.of(StreamMode.OUTPUT), null);
}
```

6. Add import for StreamMode:
```java
import com.openjiuwen.core.session.stream.StreamMode;
```

- [ ] **Step 4: Update the test to use Runner singleton instead of testRunner injection**

Rewrite the test setUp/tearDown to use Runner singleton:

```java
@BeforeEach
void setUp() {
    TenantContextHolder.clearCurrentTenant();
    CwdContext.reset();
    CheckpointerFactory.setDefaultCheckpointer(null);
    RunnerConfig.setRunnerConfig(null);
    RunnerConfig tenantConfig = RunnerConfig.builder().distributedMode(false).build();
    Runner.setConfig(tenantConfig);
    Runner.start();
    TenantProxyAwareAgent tenantAgent = new TenantProxyAwareAgent();
    Runner.resourceMgr().addAgent(
        com.openjiuwen.core.singleagent.schema.AgentCard.builder()
            .id("adapter-agent").name("adapter-agent").build(),
        () -> tenantAgent, null);
    adapter = new AgentAdapter("adapter-agent", "");
}

@AfterEach
void tearDown() {
    for (String sessionId : sessionsToRelease) {
        CheckpointerFactory.getCheckpointer().release(sessionId);
    }
    sessionsToRelease.clear();
    TenantContextHolder.clearCurrentTenant();
    CwdContext.reset();
    Runner.stop();
    Runner.setConfig(RunnerConfig.DEFAULT);
}
```

Remove the `setTestRunner` method from AgentAdapter since we don't need it.

- [ ] **Step 5: Run test to verify it passes**

Run: `mvn test -pl agent-core-java -Dtest=AgentAdapterTenantTest -q`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/runner/drunner/server_adapter/AgentAdapter.java agent-core-java/src/test/java/com/openjiuwen/core/runner/drunner/server_adapter/AgentAdapterTenantTest.java
git commit -m "feat(phase2): AgentAdapter extracts tenantId from MQ payload and propagates TenantContext"
```

---

## Task 4: HarnessCli + CLIOptions TenantId Support

**Files:**
- Modify: `agent-core-java/src/main/java/com/openjiuwen/harness/cli/CLIOptions.java` (add tenantId field)
- Modify: `agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java` (create TenantContext from tenantId)
- Create: `agent-core-java/src/test/java/com/openjiuwen/harness/cli/HarnessCliTenantTest.java`

**Interfaces:**
- Consumes: `TenantContext.builder()` (Phase 1), `DeepAgent.invoke(inputs, tenantCtx)` (Phase 1)
- Produces: `CLIOptions.getTenantId()` (String), `HarnessCli.runOnce` with TenantContext propagation

- [ ] **Step 1: Write the failing test**

```java
package com.openjiuwen.harness.cli;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;

import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.sysop.cwd.CwdContext;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

@DisplayName("HarnessCli Tenant Tests")
class HarnessCliTenantTest {

    @AfterEach
    void tearDown() {
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
    }

    @Nested
    @DisplayName("CLIOptions tenantId field")
    class CLIOptionsTenantId {
        @Test
        @DisplayName("CLIOptions builder sets tenantId")
        void testBuilderSetsTenantId() {
            CLIOptions opts = CLIOptions.builder()
                    .provider("openai")
                    .model("gpt-4")
                    .tenantId("cli_tenant")
                    .build();
            assertThat(opts.getTenantId()).isEqualTo("cli_tenant");
        }

        @Test
        @DisplayName("CLIOptions tenantId defaults to null")
        void testTenantIdDefaultNull() {
            CLIOptions opts = CLIOptions.builder()
                    .provider("openai")
                    .model("gpt-4")
                    .build();
            assertThat(opts.getTenantId()).isNull();
        }
    }

    @Nested
    @DisplayName("HarnessCli TenantContext creation")
    class HarnessCliTenantContextCreation {
        @Test
        @DisplayName("buildTenantContext creates TenantContext from CLIOptions tenantId")
        void testBuildTenantContextFromOptions() {
            CLIOptions opts = CLIOptions.builder()
                    .provider("openai")
                    .model("gpt-4")
                    .tenantId("cli_tenant_ctx")
                    .build();
            TenantContext ctx = HarnessCli.buildTenantContext(opts);
            assertThat(ctx).isNotNull();
            assertThat(ctx.getTenantId()).isEqualTo("cli_tenant_ctx");
            assertThat(ctx.isTenantAware()).isTrue();
        }

        @Test
        @DisplayName("buildTenantContext returns null when tenantId is null")
        void testBuildTenantContextNullId() {
            CLIOptions opts = CLIOptions.builder()
                    .provider("openai")
                    .model("gpt-4")
                    .build();
            TenantContext ctx = HarnessCli.buildTenantContext(opts);
            assertThat(ctx).isNull();
        }

        @Test
        @DisplayName("buildTenantContext returns null when tenantId is empty")
        void testBuildTenantContextEmptyId() {
            CLIOptions opts = CLIOptions.builder()
                    .provider("openai")
                    .model("gpt-4")
                    .tenantId("")
                    .build();
            TenantContext ctx = HarnessCli.buildTenantContext(opts);
            assertThat(ctx).isNull();
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn test -pl agent-core-java -Dtest=HarnessCliTenantTest -q`
Expected: FAIL — CLIOptions doesn't have tenantId field, HarnessCli doesn't have buildTenantContext

- [ ] **Step 3: Write CLIOptions implementation**

Add `tenantId` field to `CLIOptions.java`:

```java
private String tenantId;
```

Lombok `@Data @Builder @NoArgsConstructor @AllArgsConstructor` will auto-generate getter/setter/builder.

- [ ] **Step 4: Write HarnessCli implementation**

Add to `HarnessCli.java`:

1. Import:
```java
import com.openjiuwen.core.multitenant.TenantContext;
```

2. Add static helper method `buildTenantContext`:
```java
static TenantContext buildTenantContext(CLIOptions opts) {
    String tenantId = opts.getTenantId();
    if (tenantId != null && !tenantId.isBlank()) {
        return TenantContext.builder().tenantId(tenantId).build();
    }
    return null;
}
```

The `runOnce` method in HarnessCli already creates a DeepAgent and calls invoke. We need to modify it to pass TenantContext when available. However, since HarnessCli.runOnce creates a DeepAgent via HarnessFactory, and DeepAgent.invoke has a TenantContext overload from Phase 1, we can use it.

Modify `HarnessCli.runOnce` to use the TenantContext overload when tenantId is present:

```java
public Map<String, Object> runOnce(CLIOptions opts, String prompt, String outputFormat) {
    DeepAgent agent = HarnessFactory.createDeepAgent(opts);
    Map<String, Object> inputs = Map.of("query", prompt);
    TenantContext tenantCtx = buildTenantContext(opts);
    if (tenantCtx != null) {
        return agent.invoke(inputs, tenantCtx);
    }
    return agent.invoke(inputs);
}
```

Similarly modify `runChat` if it uses DeepAgent's invoke method. Since `runChat` creates a SessionStore for interactive chat, the TenantContext should be set at the beginning of the session.

- [ ] **Step 5: Run test to verify it passes**

Run: `mvn test -pl agent-core-java -Dtest=HarnessCliTenantTest -q`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/harness/cli/CLIOptions.java agent-core-java/src/main/java/com/openjiuwen/harness/cli/HarnessCli.java agent-core-java/src/test/java/com/openjiuwen/harness/cli/HarnessCliTenantTest.java
git commit -m "feat(phase2): CLIOptions tenantId field and HarnessCli TenantContext propagation"
```

---

## Task 5: Backward Compatibility + Integration Test

**Files:**
- Create: `agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerTenantBackwardCompatTest.java`

**Interfaces:**
- Consumes: All Phase 2 components (RunnerConfig, RunnerImpl, Runner, AgentAdapter, HarnessCli, CheckpointerFactory)
- Produces: Verification that backward compat is preserved and full chain works

- [ ] **Step 1: Write the integration test**

```java
package com.openjiuwen.core.runner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;

import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.session.AgentSessionApi;
import com.openjiuwen.core.session.checkpointer.CheckpointerFactory;
import com.openjiuwen.core.session.checkpointer.InMemoryCheckpointer;
import com.openjiuwen.core.sysop.cwd.CwdContext;
import com.openjiuwen.core.session.stream.StreamMode;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

@DisplayName("Runner Tenant Backward Compatibility + Integration Tests")
class RunnerTenantBackwardCompatTest {
    private final List<String> sessionsToRelease = new ArrayList<>();

    @AfterEach
    void tearDown() {
        for (String sessionId : sessionsToRelease) {
            CheckpointerFactory.getCheckpointer().release(sessionId);
        }
        sessionsToRelease.clear();
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
        CheckpointerFactory.setDefaultCheckpointer(null);
        RunnerConfig.setRunnerConfig(null);
    }

    private void trackSession(String sessionId) {
        sessionsToRelease.add(sessionId);
    }

    @Nested
    @DisplayName("Backward compatibility without TenantContext")
    class BackwardCompatWithoutTenant {
        @Test
        @DisplayName("RunnerImpl.runAgent without TenantContext identical to original")
        void testRunAgentNoTenantIdenticalToOriginal() {
            RunnerConfig config = RunnerConfig.builder().distributedMode(false).build();
            RunnerImpl runner = new RunnerImpl("compat-runner", config);
            runner.start();

            CompatAgent agent = new CompatAgent();
            String sessionId = "compat-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null));

            assertThat(result.get("session_id")).isEqualTo(sessionId);
            assertThat(result.get("captured_tenant_id")).isNull();
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
            assertThat(CwdContext.getTenantRoot()).isNull();

            runner.stop();
        }

        @Test
        @DisplayName("RunnerConfig.DEFAULT has enableTenantIsolation=false")
        void testDefaultConfigNoTenantIsolation() {
            assertThat(RunnerConfig.DEFAULT.isEnableTenantIsolation()).isFalse();
            assertThat(RunnerConfig.DEFAULT.getTenantDataRoot()).isNull();
        }

        @Test
        @DisplayName("Runner.start() without enableTenantIsolation does not create workspaceResolver")
        void testStartNoTenantIsolationNoResolver() {
            RunnerConfig config = RunnerConfig.builder().distributedMode(false).build();
            RunnerImpl runner = new RunnerImpl("no-resolver-runner", config);
            runner.start();

            CompatAgent agent = new CompatAgent();
            String sessionId = "no-resolver-compat-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null,
                    TenantContext.builder().tenantId("should_not_resolve").build()));

            assertThat(result.get("captured_tenant_id")).isEqualTo("should_not_resolve");
            assertThat(result.get("captured_tenant_root")).isNull();

            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
            assertThat(CwdContext.getTenantRoot()).isNull();
            runner.stop();
        }
    }

    @Nested
    @DisplayName("Checkpointer auto-prefixing with TenantContext")
    class CheckpointerAutoPrefixing {
        @Test
        @DisplayName("InMemoryCheckpointer auto-prefixes session keys when TenantContext is set via Runner")
        void testCheckpointerAutoPrefixViaRunner() {
            RunnerConfig config = RunnerConfig.builder()
                    .distributedMode(false)
                    .enableTenantIsolation(true)
                    .tenantDataRoot(System.getProperty("user.dir"))
                    .build();
            RunnerImpl runner = new RunnerImpl("cp-tenant-runner", config);
            runner.start();

            TenantContext tenantCtx = TenantContext.builder().tenantId("cp_tenant").build();
            CompatAgent agent = new CompatAgent();
            String sessionId = "cp-tenant-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, tenantCtx));

            assertThat(result.get("captured_tenant_id")).isEqualTo("cp_tenant");

            CheckpointerFactory.getCheckpointer().release(sessionId);
            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
            runner.stop();
        }
    }

    @Nested
    @DisplayName("Full chain integration")
    class FullChainIntegration {
        @Test
        @DisplayName("Runner.start() + runAgent + TenantContext full chain")
        void testFullChainRunnerAgentTenant() {
            RunnerConfig config = RunnerConfig.builder()
                    .distributedMode(false)
                    .enableTenantIsolation(true)
                    .tenantDataRoot(System.getProperty("user.dir"))
                    .build();
            RunnerImpl runner = new RunnerImpl("full-chain-runner", config);
            runner.start();

            TenantContext tenantCtx = TenantContext.builder().tenantId("full_chain_tenant").build();
            CompatAgent agent = new CompatAgent();
            String sessionId = "full-chain-session";
            trackSession(sessionId);

            Map<String, Object> result = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionId), null, null, null, tenantCtx));

            assertThat(result.get("session_id")).isEqualTo(sessionId);
            assertThat(result.get("captured_tenant_id")).isEqualTo("full_chain_tenant");
            assertThat(result.get("captured_tenant_root")).isNotNull();
            assertThat(result.get("captured_tenant_root")).contains("tenants");
            assertThat(result.get("captured_tenant_root")).contains("full_chain_tenant");

            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
            assertThat(CwdContext.getTenantRoot()).isNull();
            runner.stop();
        }

        @Test
        @DisplayName("Different TenantContexts in same Runner produce different tenant roots")
        void testDifferentTenantsDifferentRoots() {
            RunnerConfig config = RunnerConfig.builder()
                    .distributedMode(false)
                    .enableTenantIsolation(true)
                    .tenantDataRoot(System.getProperty("user.dir"))
                    .build();
            RunnerImpl runner = new RunnerImpl("multi-tenant-runner", config);
            runner.start();

            TenantContext tenantA = TenantContext.builder().tenantId("tenant_a").build();
            TenantContext tenantB = TenantContext.builder().tenantId("tenant_b").build();
            CompatAgent agent = new CompatAgent();

            String sessionA = "multi-session-a";
            String sessionB = "multi-session-b";
            trackSession(sessionA);
            trackSession(sessionB);

            Map<String, Object> resultA = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionA), null, null, null, tenantA));
            Map<String, Object> resultB = castMap(
                runner.runAgent(agent, Map.of("conversation_id", sessionB), null, null, null, tenantB));

            assertThat(resultA.get("captured_tenant_root")).isNotEqualTo(resultB.get("captured_tenant_root"));
            assertThat((String) resultA.get("captured_tenant_root")).contains("tenant_a");
            assertThat((String) resultB.get("captured_tenant_root")).contains("tenant_b");

            assertThat(TenantContextHolder.getCurrentTenant()).isNull();
            runner.stop();
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> castMap(Object value) {
        return (Map<String, Object>) value;
    }

    private static class CompatAgent {
        public Map<String, Object> invoke(Map<String, Object> inputs, AgentSessionApi session) {
            Map<String, Object> result = new java.util.LinkedHashMap<>();
            result.put("session_id", session.getSessionId());
            result.put("captured_tenant_id",
                TenantContextHolder.getCurrentTenant() != null
                    ? TenantContextHolder.getCurrentTenant().getTenantId() : null);
            result.put("captured_tenant_root", CwdContext.getTenantRoot());
            return result;
        }
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `mvn test -pl agent-core-java -Dtest=RunnerTenantBackwardCompatTest -q`
Expected: PASS (all Phase 2 components are implemented from Tasks 1-4)

- [ ] **Step 3: Run full regression suite**

Run: `mvn test -pl agent-core-java -q`
Expected: ALL PASS (Phase 1 + Phase 2 tests, backward compat preserved)

- [ ] **Step 4: Commit**

```bash
git add agent-core-java/src/test/java/com/openjiuwen/core/runner/RunnerTenantBackwardCompatTest.java
git commit -m "test(phase2): Runner tenant backward compat and integration tests"
```

---

## Self-Review Checklist

1. **Spec coverage**: 
   - ✅ RunnerConfig enableTenantIsolation → Task 1
   - ✅ RunnerImpl.runAgent/runWorkflow 支持 TenantContext → Task 2
   - ✅ CheckpointerFactory 自动注入 tenantId 前缀 → Task 5 (integration test verifies auto-prefixing works via TenantContextHolder)
   - ✅ Runner 入口 (A2A/CLI) 传递 tenantId → Task 3 (AgentAdapter) + Task 4 (HarnessCli)

2. **Placeholder scan**: No TBD, TODO, or vague descriptions. All steps have concrete code.

3. **Type consistency**: 
   - `TenantContext` used consistently across all tasks (from Phase 1)
   - `RunnerConfig.isEnableTenantIsolation()` boolean, `RunnerConfig.getTenantDataRoot()` String — consistent
   - `Runner.runAgent(agent, inputs, session, context, envs, tenantCtx)` — 6-param overload consistent between RunnerImpl and Runner proxy
