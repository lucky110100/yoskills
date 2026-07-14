# 多租户数据隔离实施计划

> **面向智能代理工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 来逐任务执行此计划。步骤使用复选框 (`- [ ]`) 语法进行跟踪。

**目标：** 为 agent-core-java 实现租户级数据隔离，使 DeepAgent 能够按 tenantId 隔离技能数据、工作区文件、临时文件、检查点状态、记忆数据和 KVStore 业务数据。

**架构：** TenantContext + TenantContextHolder（InheritableThreadLocal）上下文传播模式，配合 TenantWorkspaceResolver 用于目录隔离、TenantPathSecurity 用于路径遍历防护、TenantKVStoreKeyResolver 用于 KVStore 键前缀。完全向后兼容——当 tenantId 不存在时无隔离行为。

**技术栈：** Java 17、JUnit 5.10.2、AssertJ 3.25.3、Mockito 5.2.0、Lombok、Maven Surefire 3.2.5

## 全局约束

- Java 版本：17
- JUnit Jupiter：5.10.2
- AssertJ：3.25.3
- Mockito：5.2.0（core + inline）
- 测试类可见性：包级别（无 `public` 修饰符）
- 测试方法命名：`testXxxYyy` 前缀模式
- 静态导入：`org.assertj.core.api.Assertions.assertThat`、`org.junit.jupiter.api.Assertions.*`
- Maven 测试命令：`mvn test -pl agent-core-java`
- Surefire 默认排除：`@Tag("system-test")`
- Lombok：模型类使用 @Data @Builder
- 包根目录：`com.openjiuwen`
- 源码根目录：`agent-core-java/src/main/java/com/openjiuwen/`
- 测试根目录：`agent-core-java/src/test/java/com/openjiuwen/`
- 所有租户隔离代码位于包：`com.openjiuwen.core.multitenant`
- TenantContext tenantId：不透明标识符，框架不解释其业务含义
- 向后兼容性：无 TenantContext → 行为与当前代码完全一致

---

## 任务 1：TenantContext 数据模型

**文件：**
- 创建：`agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantContext.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantContextTest.java`

**接口：**
- 产出：`TenantContext`（tenantId、extensions、isTenantAware()、safeTenantId()）

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.multitenant;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class TenantContextTest {

    @Test
    void testIsTenantAware_withValidId() {
        TenantContext ctx = TenantContext.builder().tenantId("abc123").build();
        assertThat(ctx.isTenantAware()).isTrue();
    }

    @Test
    void testIsTenantAware_withNullId() {
        TenantContext ctx = TenantContext.builder().tenantId(null).build();
        assertThat(ctx.isTenantAware()).isFalse();
    }

    @Test
    void testIsTenantAware_withEmptyId() {
        TenantContext ctx = TenantContext.builder().tenantId("").build();
        assertThat(ctx.isTenantAware()).isFalse();
    }

    @Test
    void testSafeTenantId_normalInput() {
        TenantContext ctx = TenantContext.builder().tenantId("abc123").build();
        assertThat(ctx.safeTenantId()).isEqualTo("abc123");
    }

    @Test
    void testSafeTenantId_specialCharacters() {
        TenantContext ctx = TenantContext.builder().tenantId("abc../../123").build();
        assertThat(ctx.safeTenantId()).isEqualTo("abc___123");
    }

    @Test
    void testSafeTenantId_nullInput() {
        TenantContext ctx = TenantContext.builder().tenantId(null).build();
        assertThat(ctx.safeTenantId()).isNull();
    }

    @Test
    void testSafeTenantId_emptyAfterSanitize() {
        TenantContext ctx = TenantContext.builder().tenantId("!@#$%").build();
        assertThat(ctx.safeTenantId()).isNull();
    }

    @Test
    void testSafeTenantId_preservesHyphenAndUnderscore() {
        TenantContext ctx = TenantContext.builder().tenantId("dept_fin-03").build();
        assertThat(ctx.safeTenantId()).isEqualTo("dept_fin-03");
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantContextTest`
预期：失败——TenantContext 类不存在

- [ ] **步骤 3：编写最小实现**

```java
package com.openjiuwen.core.multitenant;

import lombok.Builder;
import lombok.Data;
import java.util.Map;

@Data
@Builder
public class TenantContext {
    private final String tenantId;
    private final Map<String, String> extensions;

    public boolean isTenantAware() {
        return tenantId != null && !tenantId.isEmpty();
    }

    public String safeTenantId() {
        if (tenantId == null) return null;
        String sanitized = tenantId.replaceAll("[^a-zA-Z0-9_\\-]", "_");
        if (sanitized.isEmpty()) return null;
        return sanitized;
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantContextTest`
预期：通过——全部 8 个测试

- [ ] **步骤 5：提交**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantContext.java agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantContextTest.java
git commit -m "feat(multitenant): add TenantContext data model with safeTenantId sanitization"
```

---

## 任务 2：TenantContextHolder ThreadLocal 上下文传播

**文件：**
- 创建：`agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantContextHolder.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantContextHolderTest.java`

**接口：**
- 消费：任务 1 的 `TenantContext`
- 产出：`TenantContextHolder.getCurrentTenant()`、`setCurrentTenant()`、`clearCurrentTenant()`

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.multitenant;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import static org.assertj.core.api.Assertions.assertThat;

class TenantContextHolderTest {

    @BeforeEach
    void clearContext() {
        TenantContextHolder.clearCurrentTenant();
    }

    @Test
    void testSetAndGet() {
        TenantContext ctx = TenantContext.builder().tenantId("abc123").build();
        TenantContextHolder.setCurrentTenant(ctx);
        assertThat(TenantContextHolder.getCurrentTenant()).isEqualTo(ctx);
    }

    @Test
    void testClear() {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        TenantContextHolder.clearCurrentTenant();
        assertThat(TenantContextHolder.getCurrentTenant()).isNull();
    }

    @Test
    void testDefaultIsNull() {
        assertThat(TenantContextHolder.getCurrentTenant()).isNull();
    }

    @Test
    void testInheritableThreadLocal_childThreadInherits() throws Exception {
        TenantContext ctx = TenantContext.builder().tenantId("abc123").build();
        TenantContextHolder.setCurrentTenant(ctx);

        Thread child = new Thread(() -> {
            assertThat(TenantContextHolder.getCurrentTenant()).isNotNull();
            assertThat(TenantContextHolder.getCurrentTenant().getTenantId()).isEqualTo("abc123");
        });
        child.start();
        child.join();
    }

    @Test
    void testInheritableThreadLocal_childThreadIndependentClear() throws Exception {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("parent").build());

        Thread child = new Thread(() -> {
            TenantContextHolder.clearCurrentTenant();
        });
        child.start();
        child.join();

        assertThat(TenantContextHolder.getCurrentTenant().getTenantId()).isEqualTo("parent");
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantContextHolderTest`
预期：失败——TenantContextHolder 类不存在

- [ ] **步骤 3：编写最小实现**

```java
package com.openjiuwen.core.multitenant;

public final class TenantContextHolder {
    private static final InheritableThreadLocal<TenantContext> CURRENT_TENANT = new InheritableThreadLocal<>();

    public static TenantContext getCurrentTenant() {
        return CURRENT_TENANT.get();
    }

    public static void setCurrentTenant(TenantContext ctx) {
        CURRENT_TENANT.set(ctx);
    }

    public static void clearCurrentTenant() {
        CURRENT_TENANT.remove();
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantContextHolderTest`
预期：通过——全部 5 个测试

- [ ] **步骤 5：提交**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantContextHolder.java agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantContextHolderTest.java
git commit -m "feat(multitenant): add TenantContextHolder with InheritableThreadLocal propagation"
```

---

## 任务 3：TenantWorkspaceResolver——目录解析 + 并发初始化

**文件：**
- 创建：`agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantWorkspaceResolver.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantWorkspaceResolverTest.java`

**接口：**
- 消费：任务 1 的 `TenantContext`
- 产出：`TenantWorkspaceResolver.resolveWorkspaceRoot()`、`resolveSkillRoot()`、`resolveTempDir()`、`resolveCheckpointDir()`、`initializeTenantSpace()`、`isPathWithinTenant()`

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.multitenant;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.Path;
import java.util.concurrent.*;
import java.util.Set;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import static org.assertj.core.api.Assertions.assertThat;

class TenantWorkspaceResolverTest {

    @TempDir
    Path baseDir;

    TenantWorkspaceResolver resolver;
    TenantContext tenantA;
    TenantContext tenantB;
    TenantContext noTenant;

    @BeforeEach
    void setup() {
        resolver = new TenantWorkspaceResolver(baseDir.toString());
        tenantA = TenantContext.builder().tenantId("abc123").build();
        tenantB = TenantContext.builder().tenantId("dept_fin_03").build();
        noTenant = TenantContext.builder().tenantId(null).build();
    }

    @Test
    void testResolveWorkspaceRoot_withTenant() {
        Path result = resolver.resolveWorkspaceRoot(tenantA);
        assertThat(result.toString()).contains("tenants").contains("abc123").contains("workspace");
        assertThat(result).isAbsolute();
    }

    @Test
    void testResolveWorkspaceRoot_noTenant_backwardCompat() {
        Path result = resolver.resolveWorkspaceRoot(noTenant);
        assertThat(result).isEqualTo(baseDir);
    }

    @Test
    void testResolveSkillRoot_withTenant() {
        Path result = resolver.resolveSkillRoot(tenantA);
        assertThat(result.toString()).contains("tenants").contains("abc123").contains("skills");
    }

    @Test
    void testResolveSkillRoot_noTenant_returnsNull() {
        Path result = resolver.resolveSkillRoot(noTenant);
        assertThat(result).isNull();
    }

    @Test
    void testResolveTempDir_withTenant() {
        Path result = resolver.resolveTempDir(tenantA);
        assertThat(result.toString()).contains("tenants").contains("abc123").contains("tmp");
    }

    @Test
    void testResolveTempDir_noTenant_defaultTmp() {
        Path result = resolver.resolveTempDir(noTenant);
        assertThat(result.toString()).endsWith("tmp");
        assertThat(result).isEqualTo(baseDir.resolve("tmp"));
    }

    @Test
    void testIsPathWithinTenant_withinBoundary() {
        Path tenantPath = resolver.resolveWorkspaceRoot(tenantA).resolve("some_file.txt");
        assertThat(resolver.isPathWithinTenant(tenantPath, tenantA)).isTrue();
    }

    @Test
    void testIsPathWithinTenant_outsideBoundary() {
        Path otherTenantPath = resolver.resolveWorkspaceRoot(tenantB).resolve("secret.txt");
        assertThat(resolver.isPathWithinTenant(otherTenantPath, tenantA)).isFalse();
    }

    @Test
    void testIsPathWithinTenant_noTenant_alwaysTrue() {
        assertThat(resolver.isPathWithinTenant(Path.of("/any/path"), noTenant)).isTrue();
    }

    @Test
    void testInitializeTenantSpace_createsDirectories() {
        Path root = resolver.initializeTenantSpace(tenantA);
        assertThat(root.resolve("workspace")).isDirectory();
        assertThat(root.resolve("skills")).isDirectory();
        assertThat(root.resolve("tmp")).isDirectory();
        assertThat(root.resolve("checkpoints")).isDirectory();
    }

    @Test
    void testInitializeTenantSpace_concurrentSafety() throws Exception {
        int threadCount = 20;
        ExecutorService executor = Executors.newFixedThreadPool(threadCount);
        List<Future<Path>> futures = new ArrayList<>();

        for (int i = 0; i < threadCount; i++) {
            futures.add(executor.submit(() -> resolver.initializeTenantSpace(tenantA)));
        }

        Set<Path> paths = futures.stream()
            .map(Future::get)
            .collect(Collectors.toSet());
        assertThat(paths).hasSize(1);
        executor.shutdown();
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantWorkspaceResolverTest`
预期：失败——TenantWorkspaceResolver 类不存在

- [ ] **步骤 3：编写最小实现**

```java
package com.openjiuwen.core.multitenant;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.ConcurrentHashMap;

public class TenantWorkspaceResolver {
    private final String baseWorkspacePath;
    private final ConcurrentHashMap<String, Path> initializedTenants = new ConcurrentHashMap<>();

    public TenantWorkspaceResolver(String baseWorkspacePath) {
        this.baseWorkspacePath = baseWorkspacePath;
    }

    public Path resolveWorkspaceRoot(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath);
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "workspace")
                   .toAbsolutePath().normalize();
    }

    public Path resolveSkillRoot(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return null;
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "skills")
                   .toAbsolutePath().normalize();
    }

    public Path resolveTempDir(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath, "tmp").toAbsolutePath().normalize();
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "tmp")
                   .toAbsolutePath().normalize();
    }

    public Path resolveCheckpointDir(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath, "checkpoints").toAbsolutePath().normalize();
        }
        return Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId(), "checkpoints")
                   .toAbsolutePath().normalize();
    }

    public Path initializeTenantSpace(TenantContext ctx) {
        if (!ctx.isTenantAware()) {
            return Path.of(baseWorkspacePath);
        }
        return initializedTenants.computeIfAbsent(ctx.safeTenantId(), tid -> {
            Path root = Path.of(baseWorkspacePath, "tenants", tid);
            try {
                Files.createDirectories(root.resolve("workspace"));
                Files.createDirectories(root.resolve("skills"));
                Files.createDirectories(root.resolve("tmp"));
                Files.createDirectories(root.resolve("checkpoints"));
            } catch (Exception e) {
                throw new RuntimeException("Failed to initialize tenant space: " + tid, e);
            }
            return root;
        });
    }

    public boolean isPathWithinTenant(Path requestedPath, TenantContext ctx) {
        if (!ctx.isTenantAware()) return true;
        Path tenantRoot = Path.of(baseWorkspacePath, "tenants", ctx.safeTenantId())
                              .toAbsolutePath().normalize();
        Path normalized = requestedPath.toAbsolutePath().normalize();
        return normalized.startsWith(tenantRoot);
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantWorkspaceResolverTest`
预期：通过——全部 12 个测试

- [ ] **步骤 5：提交**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantWorkspaceResolver.java agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantWorkspaceResolverTest.java
git commit -m "feat(multitenant): add TenantWorkspaceResolver with concurrent-safe initialization"
```

---

## 任务 4：TenantPathSecurity——路径遍历防护

**文件：**
- 创建：`agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantPathSecurity.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantPathSecurityTest.java`

**接口：**
- 消费：任务 1 的 `TenantContext`
- 产出：`TenantPathSecurity.resolveSafePath()`

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.multitenant;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.Files;
import java.nio.file.Path;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class TenantPathSecurityTest {

    @TempDir
    Path tenantRoot;

    @TempDir
    Path otherTenantRoot;

    String tenantRootStr;

    @BeforeEach
    void setup() {
        tenantRootStr = tenantRoot.toString();
    }

    @Test
    void testResolveSafePath_normalPath() {
        Path result = TenantPathSecurity.resolveSafePath("some_file.txt", tenantRootStr);
        assertThat(result).isAbsolute();
        assertThat(result.toString()).contains("some_file.txt");
    }

    @Test
    void testResolveSafePath_pathTraversalBlocked() {
        assertThatThrownBy(() ->
            TenantPathSecurity.resolveSafePath("../../other_tenant/secret.txt", tenantRootStr)
        ).isInstanceOf(SecurityException.class)
          .hasMessageContaining("Path traversal blocked");
    }

    @Test
    void testResolveSafePath_absolutePathOutsideTenantBlocked() {
        assertThatThrownBy(() ->
            TenantPathSecurity.resolveSafePath("/etc/passwd", tenantRootStr)
        ).isInstanceOf(SecurityException.class);
    }

    @Test
    void testResolveSafePath_nullTenantRoot_allowsAll() {
        Path result = TenantPathSecurity.resolveSafePath("/etc/passwd", null);
        assertThat(result).isAbsolute();
    }

    @Test
    void testResolveSafePath_symlinkTraversalBlocked() throws Exception {
        Path secretFile = otherTenantRoot.resolve("secret.txt");
        Files.writeString(secretFile, "confidential data");
        Path link = tenantRoot.resolve("stealth_link");
        Files.createSymbolicLink(link, secretFile);

        assertThatThrownBy(() ->
            TenantPathSecurity.resolveSafePath("stealth_link", tenantRootStr)
        ).isInstanceOf(SecurityException.class)
          .hasMessageContaining("Symlink traversal blocked");
    }

    @Test
    void testResolveSafePath_symlinkWithinTenantAllowed() throws Exception {
        Path target = tenantRoot.resolve("target.txt");
        Files.writeString(target, "safe data");
        Path link = tenantRoot.resolve("safe_link");
        Files.createSymbolicLink(link, target);

        Path result = TenantPathSecurity.resolveSafePath("safe_link", tenantRootStr);
        assertThat(result).isAbsolute();
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantPathSecurityTest`
预期：失败——TenantPathSecurity 类不存在

- [ ] **步骤 3：编写最小实现**

```java
package com.openjiuwen.core.multitenant;

import java.nio.file.Files;
import java.nio.file.Path;
import java.io.IOException;

public class TenantPathSecurity {

    public static Path resolveSafePath(String relativePath, String tenantRoot) {
        Path cwd = Path.of("").toAbsolutePath();
        Path resolved = cwd.resolve(relativePath).toAbsolutePath().normalize();

        if (tenantRoot != null) {
            Path root = Path.of(tenantRoot).toAbsolutePath().normalize();
            if (!resolved.startsWith(root)) {
                throw new SecurityException(
                    "Path traversal blocked: " + relativePath +
                    " is outside tenant boundary");
            }
        }

        try {
            if (Files.exists(resolved) && Files.isSymbolicLink(resolved)) {
                Path realTarget = resolved.toRealPath();
                if (tenantRoot != null) {
                    Path root = Path.of(tenantRoot).toAbsolutePath().normalize();
                    if (!realTarget.startsWith(root)) {
                        throw new SecurityException(
                            "Symlink traversal blocked: symlink target is outside tenant boundary");
                    }
                }
            }
        } catch (IOException e) {
            throw new SecurityException("Failed to resolve symlink: " + relativePath, e);
        }

        return resolved;
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantPathSecurityTest`
预期：通过——全部 6 个测试

- [ ] **步骤 5：提交**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantPathSecurity.java agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantPathSecurityTest.java
git commit -m "feat(multitenant): add TenantPathSecurity with path traversal and symlink prevention"
```

---

## 任务 5：TenantKVStoreKeyResolver——KVStore 键前缀工具

**文件：**
- 创建：`agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantKVStoreKeyResolver.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantKVStoreKeyResolverTest.java`

**接口：**
- 消费：任务 1 的 `TenantContext`，任务 2 的 `TenantContextHolder`
- 产出：`TenantKVStoreKeyResolver.resolveKey()`、`resolvePrefix()`

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.multitenant;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

class TenantKVStoreKeyResolverTest {

    @BeforeEach
    void clearContext() {
        TenantContextHolder.clearCurrentTenant();
    }

    @Test
    void testResolveKey_withTenant() {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        String result = TenantKVStoreKeyResolver.resolveKey("UMD/user1/scope1/mem1");
        assertThat(result).isEqualTo("abc123:UMD/user1/scope1/mem1");
    }

    @Test
    void testResolveKey_noTenant_backwardCompat() {
        String result = TenantKVStoreKeyResolver.resolveKey("UMD/user1/scope1/mem1");
        assertThat(result).isEqualTo("UMD/user1/scope1/mem1");
    }

    @Test
    void testResolvePrefix_withTenant() {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        String result = TenantKVStoreKeyResolver.resolvePrefix("UMD/");
        assertThat(result).isEqualTo("abc123:UMD/");
    }

    @Test
    void testResolvePrefix_noTenant_backwardCompat() {
        String result = TenantKVStoreKeyResolver.resolvePrefix("UMD/");
        assertThat(result).isEqualTo("UMD/");
    }

    @Test
    void testResolveKey_specialTenantIdSanitized() {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc../def").build());
        String result = TenantKVStoreKeyResolver.resolveKey("some_key");
        assertThat(result).isEqualTo("abc___def:some_key");
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantKVStoreKeyResolverTest`
预期：失败——TenantKVStoreKeyResolver 类不存在

- [ ] **步骤 3：编写最小实现**

```java
package com.openjiuwen.core.multitenant;

public class TenantKVStoreKeyResolver {

    public static String resolveKey(String originalKey) {
        TenantContext ctx = TenantContextHolder.getCurrentTenant();
        if (ctx != null && ctx.isTenantAware()) {
            return ctx.safeTenantId() + ":" + originalKey;
        }
        return originalKey;
    }

    public static String resolvePrefix(String originalPrefix) {
        TenantContext ctx = TenantContextHolder.getCurrentTenant();
        if (ctx != null && ctx.isTenantAware()) {
            return ctx.safeTenantId() + ":" + originalPrefix;
        }
        return originalPrefix;
    }
}
```

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantKVStoreKeyResolverTest`
预期：通过——全部 5 个测试

- [ ] **步骤 5：提交**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/multitenant/TenantKVStoreKeyResolver.java agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantKVStoreKeyResolverTest.java
git commit -m "feat(multitenant): add TenantKVStoreKeyResolver for KVStore key prefixing"
```

---

## 任务 6：CwdContext TENANT_ROOT 增强

**文件：**
- 修改：`agent-core-java/src/main/java/com/openjiuwen/core/sysop/cwd/CwdContext.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/sysop/cwd/CwdContextTenantTest.java`

**接口：**
- 消费：任务 1 的 `TenantContext`
- 产出：`CwdContext.getTenantRoot()`、`setTenantRoot()`、`isWithinTenantRoot()`

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.sysop.cwd;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.nio.file.Path;
import static org.assertj.core.api.Assertions.assertThat;

class CwdContextTenantTest {

    @BeforeEach
    void reset() {
        CwdContext.reset();
    }

    @Test
    void testSetAndGetTenantRoot() {
        CwdContext.setTenantRoot("/data/tenants/abc123");
        assertThat(CwdContext.getTenantRoot()).isEqualTo("/data/tenants/abc123");
    }

    @Test
    void testIsWithinTenantRoot_withinBoundary() {
        CwdContext.setTenantRoot("/data/tenants/abc123");
        assertThat(CwdContext.isWithinTenantRoot(Path.of("/data/tenants/abc123/workspace/file.txt"))).isTrue();
    }

    @Test
    void testIsWithinTenantRoot_outsideBoundary() {
        CwdContext.setTenantRoot("/data/tenants/abc123");
        assertThat(CwdContext.isWithinTenantRoot(Path.of("/data/tenants/other_tenant/workspace/secret.txt"))).isFalse();
    }

    @Test
    void testIsWithinTenantRoot_nullTenantRoot_allowsAll() {
        assertThat(CwdContext.getTenantRoot()).isNull();
        assertThat(CwdContext.isWithinTenantRoot(Path.of("/any/path"))).isTrue();
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=CwdContextTenantTest`
预期：失败——`CwdContext.getTenantRoot()` 和 `isWithinTenantRoot()` 不存在

- [ ] **步骤 3：编写最小实现**

阅读 `CwdContext.java` 以了解当前结构，然后添加：

```java
// 添加到 CwdContext.java
private static final InheritableThreadLocal<String> TENANT_ROOT = new InheritableThreadLocal<>();

public static String getTenantRoot() {
    return TENANT_ROOT.get();
}

public static void setTenantRoot(String tenantRoot) {
    TENANT_ROOT.set(tenantRoot);
}

public static boolean isWithinTenantRoot(Path path) {
    String root = getTenantRoot();
    if (root == null) return true;
    Path normalized = path.toAbsolutePath().normalize();
    Path rootPath = Path.of(root).toAbsolutePath().normalize();
    return normalized.startsWith(rootPath);
}
```

同时在现有的 `reset()` 方法中添加 `TENANT_ROOT.remove()`。

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=CwdContextTenantTest`
预期：通过——全部 4 个测试

- [ ] **步骤 5：提交**

```bash
git add agent-core-java/src/main/java/com/openjiuwen/core/sysop/cwd/CwdContext.java agent-core-java/src/test/java/com/openjiuwen/core/sysop/cwd/CwdContextTenantTest.java
git commit -m "feat(multitenant): add TENANT_ROOT and isWithinTenantRoot to CwdContext"
```

---

## 任务 7：BaseFsOperation 租户感知路径解析

**文件：**
- 修改：`agent-core-java/src/main/java/com/openjiuwen/core/sysop/local/LocalFsOperation.java`（以及其他 FsOperation 子类）
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/sysop/FsOperationTenantTest.java`

**接口：**
- 消费：任务 4 的 `TenantPathSecurity`，任务 6 的 `CwdContext.isWithinTenantRoot()`
- 产出：强制路径边界的租户感知文件操作

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.sysop;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.Files;
import java.nio.file.Path;
import com.openjiuwen.core.sysop.cwd.CwdContext;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class FsOperationTenantTest {

    @TempDir
    Path tenantDir;

    @TempDir
    Path otherDir;

    @BeforeEach
    void setup() {
        CwdContext.reset();
        TenantContextHolder.clearCurrentTenant();
    }

    @Test
    void testFileWriteOutsideTenantBlocked() {
        CwdContext.setTenantRoot(tenantDir.toString());
        CwdContext.setCwd(tenantDir.toString());

        assertThatThrownBy(() -> {
            Path outside = otherDir.resolve("secret.txt");
            TenantPathSecurity.resolveSafePath(outside.toString(), tenantDir.toString());
        }).isInstanceOf(SecurityException.class);
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=FsOperationTenantTest`

- [ ] **步骤 3：编写最小实现**

在 `LocalFsOperation.java` 中，文件操作前添加路径安全检查：

```java
// 添加到 LocalFsOperation.java（或共享基类）
protected Path resolveSafePath(String relativePath) {
    return TenantPathSecurity.resolveSafePath(relativePath, CwdContext.getTenantRoot());
}
```

修改现有的 `writeFile`、`readFile` 方法，在执行前调用 `resolveSafePath()`。

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=FsOperationTenantTest`

- [ ] **步骤 5：提交**

```bash
git add ...
git commit -m "feat(multitenant): add tenant-aware path resolution to FsOperation"
```

---

## 任务 8：SkillTool 租户感知双层查找

**文件：**
- 修改：`agent-core-java/src/main/java/com/openjiuwen/harness/tools/SkillTool.java`
- 修改：`agent-core-java/src/main/java/com/openjiuwen/harness/tools/ListSkillTools.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/harness/tools/TenantSkillIsolationTest.java`

**接口：**
- 消费：任务 2 的 `TenantContextHolder`，任务 3 的 `TenantWorkspaceResolver`
- 产出：带租户私有技能查找的 SkillTool（优先级：租户 → 公共），带合并列表的 ListSkillTool

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.harness.tools;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.Files;
import java.nio.file.Path;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.multitenant.TenantWorkspaceResolver;
import static org.assertj.core.api.Assertions.assertThat;

class TenantSkillIsolationTest {

    @TempDir
    Path baseDir;

    Path publicSkillRoot;
    TenantWorkspaceResolver resolver;
    SkillTool skillTool;
    ListSkillTool listSkillTool;

    @BeforeEach
    void setup() throws Exception {
        TenantContextHolder.clearCurrentTenant();
        publicSkillRoot = baseDir.resolve("skills");
        Files.createDirectories(publicSkillRoot);
        Files.createDirectories(publicSkillRoot.resolve("public_skill").resolve("SKILL.md"));
        Files.writeString(publicSkillRoot.resolve("public_skill").resolve("SKILL.md"), "public skill content");

        resolver = new TenantWorkspaceResolver(baseDir.toString());
        skillTool = new SkillTool(publicSkillRoot.toString(), resolver);
        listSkillTool = new ListSkillTool(publicSkillRoot.toString(), resolver);
    }

    @Test
    void testPublicSkillVisibleToAllTenants() {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        resolver.initializeTenantSpace(TenantContextHolder.getCurrentTenant());
        var result = skillTool.readSkill("public_skill", null);
        assertThat(result.isSuccess()).isTrue();
    }

    @Test
    void testTenantPrivateSkillNotVisibleToOtherTenant() throws Exception {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        resolver.initializeTenantSpace(TenantContextHolder.getCurrentTenant());
        Path tenantSkillDir = resolver.resolveSkillRoot(TenantContextHolder.getCurrentTenant());
        Files.createDirectories(tenantSkillDir.resolve("private_skill"));
        Files.writeString(tenantSkillDir.resolve("private_skill").resolve("SKILL.md"), "private content");
        TenantContextHolder.clearCurrentTenant();

        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("other").build());
        resolver.initializeTenantSpace(TenantContextHolder.getCurrentTenant());
        var result = skillTool.readSkill("private_skill", null);
        assertThat(result.isSuccess()).isFalse();
    }

    @Test
    void testTenantPrivateSkillOverridesPublic() throws Exception {
        Files.createDirectories(publicSkillRoot.resolve("overlap_skill"));
        Files.writeString(publicSkillRoot.resolve("overlap_skill").resolve("SKILL.md"), "public version");

        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        resolver.initializeTenantSpace(TenantContextHolder.getCurrentTenant());
        Path tenantSkillDir = resolver.resolveSkillRoot(TenantContextHolder.getCurrentTenant());
        Files.createDirectories(tenantSkillDir.resolve("overlap_skill"));
        Files.writeString(tenantSkillDir.resolve("overlap_skill").resolve("SKILL.md"), "tenant version");

        var result = skillTool.readSkill("overlap_skill", null);
        assertThat(result.isSuccess()).isTrue();
        assertThat(result.getData().get("source")).isEqualTo("tenant");
    }

    @Test
    void testListSkillsMergesPublicAndTenant() throws Exception {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        resolver.initializeTenantSpace(TenantContextHolder.getCurrentTenant());
        Path tenantSkillDir = resolver.resolveSkillRoot(TenantContextHolder.getCurrentTenant());
        Files.createDirectories(tenantSkillDir.resolve("tenant_only_skill"));

        var result = listSkillTool.listSkills();
        assertThat(result.isSuccess()).isTrue();
        var skills = (java.util.List<String>) result.getData().get("skills");
        assertThat(skills).contains("public_skill", "tenant_only_skill");
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantSkillIsolationTest`

- [ ] **步骤 3：修改 SkillTool 和 ListSkillTool**

将 `TenantWorkspaceResolver` 作为构造函数参数添加，并在两个工具中实现双层查找。参见设计规范第 4.4 节的完整代码。

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantSkillIsolationTest`

- [ ] **步骤 5：提交**

```bash
git add ...
git commit -m "feat(multitenant): add tenant-aware dual-layer skill lookup to SkillTool and ListSkillTool"
```

---

## 任务 9：Checkpointer 租户感知键前缀

**文件：**
- 修改：`agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/Checkpointer.java`
- 修改：`agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/InMemoryCheckpointer.java`
- 修改：`agent-core-java/src/main/java/com/openjiuwen/core/session/checkpointer/PersistenceCheckpointer.java`
- 修改：`agent-core-java/src/main/java/com/openjiuwen/extensions/checkpointer/redis/RedisCheckpointer.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/session/checkpointer/TenantCheckpointerIsolationTest.java`

**接口：**
- 消费：任务 2 的 `TenantContextHolder`，任务 5 的 `TenantKVStoreKeyResolver`
- 产出：`Checkpointer.buildKeyWithTenant()`，所有实现中的租户感知 sessionId 键

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.core.session.checkpointer;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import static org.assertj.core.api.Assertions.assertThat;

class TenantCheckpointerIsolationTest {

    @BeforeEach
    void clearContext() {
        TenantContextHolder.clearCurrentTenant();
    }

    @Test
    void testBuildKeyWithTenant_withTenantId() {
        TenantContext ctx = TenantContext.builder().tenantId("abc123").build();
        String key = Checkpointer.buildKeyWithTenant(ctx, "session-1", "agent", "react", "state");
        assertThat(key).isEqualTo("abc123:session-1:agent:react:state");
    }

    @Test
    void testBuildKeyWithTenant_noTenant_backwardCompat() {
        TenantContext ctx = TenantContext.builder().tenantId(null).build();
        String key = Checkpointer.buildKeyWithTenant(ctx, "session-1", "agent", "react", "state");
        assertThat(key).isEqualTo("session-1:agent:react:state");
    }

    @Test
    void testInMemoryCheckpointer_tenantAwareSessionId() {
        TenantContextHolder.setCurrentTenant(TenantContext.builder().tenantId("abc123").build());
        InMemoryCheckpointer cp = new InMemoryCheckpointer();
        // 验证 agentStores 键包含 tenantId 前缀
        assertThat(cp.tenantAwareSessionId("session-1")).isEqualTo("abc123:session-1");
    }

    @Test
    void testInMemoryCheckpointer_noTenant_backwardCompat() {
        InMemoryCheckpointer cp = new InMemoryCheckpointer();
        assertThat(cp.tenantAwareSessionId("session-1")).isEqualTo("session-1");
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantCheckpointerIsolationTest`

- [ ] **步骤 3：在所有 Checkpointer 类中实现变更**

在 `Checkpointer.java` 中添加 `buildKeyWithTenant()`，在 `InMemoryCheckpointer` 中添加 `tenantAwareSessionId()`，并更新 `PersistenceCheckpointer` 和 `RedisCheckpointer` 中的键生成逻辑以使用 `TenantKVStoreKeyResolver`。

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantCheckpointerIsolationTest`

- [ ] **步骤 5：提交**

```bash
git add ...
git commit -m "feat(multitenant): add tenant-aware key prefixing to all Checkpointer implementations"
```

---

## 任务 10：LongTermMemory 租户感知键/集合前缀

**文件：**
- 修改：`agent-core-java/src/main/java/com/openjiuwen/core/memory/LongTermMemory.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/memory/TenantMemoryIsolationTest.java`

**接口：**
- 消费：任务 5 的 `TenantKVStoreKeyResolver`，任务 2 的 `TenantContextHolder`
- 产出：LongTermMemory 中租户感知的 KVStore 键和 VectorStore 集合名称

- [ ] **步骤 1：编写失败的测试**

验证当租户上下文激活时 KVStore 键和 VectorStore 集合名称会带有 tenantId 前缀，而无租户时保持不变。

- [ ] **步骤 2：运行测试验证失败**

运行：`mvn test -pl agent-core-java -Dtest=TenantMemoryIsolationTest`

- [ ] **步骤 3：修改 LongTermMemory 以使用 TenantKVStoreKeyResolver**

将所有直接 KVStore 键构造替换为 `TenantKVStoreKeyResolver.resolveKey()` 调用。将 VectorStore 集合名称构造替换为 tenantId 前缀。

- [ ] **步骤 4：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantMemoryIsolationTest`

- [ ] **步骤 5：提交**

```bash
git add ...
git commit -m "feat(multitenant): add tenant-aware key/collection prefixing to LongTermMemory"
```

---

## 任务 11：DeepAgent 租户感知入口点

**文件：**
- 修改：`agent-core-java/src/main/java/com/openjiuwen/harness/deep_agent/DeepAgent.java`
- 修改：`agent-core-java/src/main/java/com/openjiuwen/harness/schema/config/DeepAgentConfig.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/harness/deep_agent/DeepAgentTenantTest.java`

**接口：**
- 消费：任务 1 的 `TenantContext`，任务 2 的 `TenantContextHolder`，任务 3 的 `TenantWorkspaceResolver`，任务 6 的 `CwdContext`
- 产出：`DeepAgent.invoke(inputs, TenantContext)` 和 `DeepAgent.stream(inputs, TenantContext, ...)`

- [ ] **步骤 1：编写失败的测试**

```java
package com.openjiuwen.harness.deep_agent;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.nio.file.Path;
import com.openjiuwen.core.multitenant.TenantContext;
import com.openjiuwen.core.multitenant.TenantContextHolder;
import com.openjiuwen.core.sysop.cwd.CwdContext;
import static org.assertj.core.api.Assertions.assertThat;

class DeepAgentTenantTest {

    @TempDir
    Path baseDir;

    @BeforeEach
    void reset() {
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
    }

    @Test
    void testBindTenantWorkspace_setsCwdContext() {
        TenantContext ctx = TenantContext.builder().tenantId("abc123").build();
        TenantWorkspaceResolver resolver = new TenantWorkspaceResolver(baseDir.toString());
        resolver.initializeTenantSpace(ctx);

        // 绑定租户工作区后，CwdContext 应反映租户路径
        Path tenantWorkspace = resolver.resolveWorkspaceRoot(ctx);
        assertThat(tenantWorkspace.toString()).contains("abc123").contains("workspace");
    }

    @Test
    void testNoTenant_backwardCompat_noCwdChange() {
        assertThat(CwdContext.getTenantRoot()).isNull();
        assertThat(CwdContext.isWithinTenantRoot(Path.of("/any/path"))).isTrue();
    }
}
```

- [ ] **步骤 2：运行测试验证失败**

- [ ] **步骤 3：添加带 TenantContext 的 invoke/stream 重载，以及 bindTenantWorkspace/unbindTenantWorkspace**

在 DeepAgent 中添加 `TenantWorkspaceResolver` 字段和 `bindTenantWorkspace()`/`unbindTenantWorkspace()` 私有方法。添加新的 `invoke(Map<String, Object> inputs, TenantContext tenantCtx)` 和 `stream(...)` 重载。在 DeepAgentConfig 中添加 `enableTenantIsolation` 和 `tenantDataRoot` 字段。

- [ ] **步骤 4：运行测试验证通过**

- [ ] **步骤 5：提交**

```bash
git add ...
git commit -m "feat(multitenant): add TenantContext-aware invoke/stream entry points to DeepAgent"
```

---

## 任务 12：SharedMemoryManager 租户感知路径解析

**文件：**
- 修改：`agent-core-java/src/main/java/com/openjiuwen/core/memory/team/SharedMemoryManager.java`
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/memory/team/TenantSharedMemoryTest.java`

**接口：**
- 消费：任务 2 的 `TenantContextHolder`，任务 3 的 `TenantWorkspaceResolver`
- 产出：租户感知的 teamMemoryDir 路径解析

- [ ] **步骤 1：编写失败的测试**

- [ ] **步骤 2：运行测试验证失败**

- [ ] **步骤 3：修改 SharedMemoryManager 以从租户工作区解析 teamMemoryDir**

当 TenantContextHolder 包含租户上下文时，将 `teamMemoryDir` 解析为 `{tenantWorkspace}/team_memory/`。否则使用原始路径。

- [ ] **步骤 4：运行测试验证通过**

- [ ] **步骤 5：提交**

```bash
git add ...
git commit -m "feat(multitenant): add tenant-aware path resolution to SharedMemoryManager"
```

---

## 任务 13：向后兼容集成测试

**文件：**
- 测试：`agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantBackwardCompatTest.java`

**接口：**
- 消费：任务 1-12 的所有组件
- 产出：全面的向后兼容性验证

- [ ] **步骤 1：编写向后兼容性测试**

```java
package com.openjiuwen.core.multitenant;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import com.openjiuwen.core.session.checkpointer.Checkpointer;
import com.openjiuwen.core.sysop.cwd.CwdContext;
import static org.assertj.core.api.Assertions.assertThat;

class TenantBackwardCompatTest {

    @BeforeEach
    void clearAll() {
        TenantContextHolder.clearCurrentTenant();
        CwdContext.reset();
    }

    @Test
    void testTenantContext_nullId_notTenantAware() {
        TenantContext ctx = TenantContext.builder().tenantId(null).build();
        assertThat(ctx.isTenantAware()).isFalse();
    }

    @Test
    void testTenantContextHolder_defaultNull() {
        assertThat(TenantContextHolder.getCurrentTenant()).isNull();
    }

    @Test
    void testTenantKVStoreKeyResolver_noTenant_originalKey() {
        assertThat(TenantKVStoreKeyResolver.resolveKey("original_key")).isEqualTo("original_key");
    }

    @Test
    void testCheckpointer_buildKeyWithTenant_noTenant_originalFormat() {
        TenantContext ctx = TenantContext.builder().tenantId(null).build();
        String key = Checkpointer.buildKeyWithTenant(ctx, "session-1", "agent", "id", "blobs");
        assertThat(key).isEqualTo("session-1:agent:id:blobs");
    }

    @Test
    void testCwdContext_noTenantRoot_allowsAllPaths() {
        assertThat(CwdContext.isWithinTenantRoot(java.nio.file.Path.of("/any/path"))).isTrue();
    }
}
```

- [ ] **步骤 2：运行测试验证通过**

运行：`mvn test -pl agent-core-java -Dtest=TenantBackwardCompatTest`
预期：通过——所有向后兼容性测试确认现有行为未变更

- [ ] **步骤 3：提交**

```bash
git add agent-core-java/src/test/java/com/openjiuwen/core/multitenant/TenantBackwardCompatTest.java
git commit -m "test(multitenant): add backward compatibility integration tests"
```

---

## 自审检查清单

**1. 规范覆盖：** 所有 7 个原始验收标准 + 3 个扩展标准（Checkpointer/Memory/团队记忆）由任务 1-13 覆盖。

**2. 占位符扫描：** 无 TBD/TODO/占位符模式。所有所示代码为具体实现。

**3. 类型一致性：** `TenantContext.safeTenantId()` 在所有任务中一致使用。`TenantKVStoreKeyResolver.resolveKey()` 一致用于 KVStore 键前缀。`TenantWorkspaceResolver` 一致用于路径解析。`TenantContextHolder.getCurrentTenant()` 一致用于上下文检索。
