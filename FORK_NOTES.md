# Fork 维护策略（Enternalcode/shadowing-english）

> 目标：在上游 TideSparrow/shadowing-english 快速迭代的同时，最小化自家改动的合并成本。
> 上游几乎每周发版（v0.2.12 → v0.3.2 约三周），不同步 = 半年后合不动。

## Remote 布局（已配好）

- `origin` = Enternalcode/shadowing-english（你的 fork，读写）
- `upstream` = TideSparrow/shadowing-english（上游，只读）

## 三条铁律

1. **`main` 永远不写自己的提交。** main 只跟踪上游，sync 时永远 fast-forward、零冲突：
   ```powershell
   git fetch upstream
   git checkout main; git merge --ff-only upstream/main; git push origin main
   ```
2. **自己的功能只进新文件、新目录。** 计划中的「打字听写」模块放
   `lib/features/dictation/`（独立页面、独立 provider、独立测试），
   对存量文件只动"接入点"：路由表 + 侧边导航入口，控制在 ≤3 个文件、每处 ≤5 行。
   新文件永远不会和上游冲突；冲突只会出现在接入点，机械可解。
3. **功能分支定期回并，不等攒大。** 开发中每 1-2 周（或上游每次发版）执行：
   ```powershell
   git checkout feature/dictation
   git merge main          # 冲突面=接入点那几行
   ```
   频繁小合并 < 攒半年一次大合并。上游动过的文件若正好是你的接入点，冲突也一目了然。

## 为什么不用 rebase 养功能分支

可以，但没必要：这个 fork 只有你自己用，`merge main` 留下的合并提交无所谓；
rebase 更适合要回提上游的场景。

## 备选出口（成本从低到高）

- **不回并，做成伴随工具**：dictation.html 已覆盖打字听写，零维护 —— 已完成。
- **提 PR 给上游**：作者迭代极快，"听写模式"是合理通用需求，被收编后你零维护。
  值得认真考虑，尤其当功能做得足够干净时（独立目录 + 最小接入）。
- **fork 自持**：上面的三条铁律。接入点清单开发时实时更新到下表。

## 接入点清单（开发时维护）

| 文件 | 改了什么 | 风险 |
|---|---|---|
| （待定，预估：路由表 `lib/router*.dart`、侧边导航、`pubspec.yaml` 无新增依赖最好） | | |

## 构建环境

- Flutter：项目锁 **3.44.4**（`.fvmrc`；`sdk: ^3.10.0`）。
  本机 `D:\Softwares\flutter` 是 3.33 旧 master，**不要动它**；
  单独装 `D:\Softwares\flutter-3.44.4`（一软件一目录）。
- 不用 FVM 也行：直接用该目录下的 `bin\flutter.bat`。
- Windows 桌面构建需 Visual Studio（已装 `D:\Softwares\Microsoft Visual Studio`）。
- 首跑：`bin\flutter.bat pub get` → `bin\flutter.bat run -d windows`。
