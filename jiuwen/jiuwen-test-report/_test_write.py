# -*- coding: utf-8 -*-
"""
Parse JiuwenTestJava surefire-reports XMLs and produce an Excel report.

Header row: 模块名 | 用例文件名 | 状态 | 优先级 | 不通过原因 | 用例目录
Priority rules:
  P0 真实失败：普通断言 / 计算结果错误 / 异常未捕获等
  P1 核心能力缺失/未实现/阻塞型缺口 (UnsupportedOperationException, NoSuch*, NoClassDefFound, "not implemented" 等)
  P2 模块返回不一致/行为结果不对齐 (结构/包装/类型差异、ClassCast、应抛而未抛)
  P3 环境依赖/真实模型/Deferred/Python 原始 skip (skipped、网络/404/连接拒绝/Disabled/真实 LLM)
  P4 通过
"""
import os
import sys
print("hello")
