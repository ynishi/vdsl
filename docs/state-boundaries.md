# State Boundaries

vdsl 関連の成果物・状態がどこに住み、誰が所有し、git 管理するかしないかの境界線を 1 箇所に固定する文書。実装 (vdsl Lua / vdsl-mcp / luarocks 配布物) の所在判断と、user の運用 (project の置き場 / .gitignore) の両方が、この文書の境界に従う。

## 1. 三つの軸

| 軸 | 役割 | 例 |
|---|---|---|
| **portable** | 1 単位だけで自己完結し、外に持ち出して再生できる | PNG (recipe + workflow tEXt) |
| **environment-bound** | credentials / endpoint / pod state に紐付く | Profile (B2 routes, env, custom_nodes) |
| **workflow-state** | その project の作業履歴 / 中間成果 / 自由 Lua | notes / journal / sweeps / src |

vdsl 本体 (Lua module) は portable 層を扱う。MCP (vdsl-mcp) は environment-bound 層と workflow-state 層を扱う。

## 2. 実行モデル: 未決 (Top Level 設計が先行する)

vdsl + vdsl-mcp の実行モデルは現状**未決**である。過去に Layer 1/2 (project root を抽象する案、`<ProjectDir>/.vdsl/` + `~/.vdsl/` Hub) を一度実装したが、`vdsl-mcp` 側 sync system が project root 抽象を一切貫通せず、SingleGlobalForSinglePC 前提のまま動いていた (`vdsl-mcp` v0.6.0 a8100a9 で切り戻し済)。物理配置だけ先に決めて Top Level 設計を後回しにすると空 spec になる、という教訓を反映し、本節は **設計が確定するまで物理配置を仕様化しない** ことを宣言する。

決めるべき Top Level 設計 (現状未決):

1. **Lua 実行モデル** — vdsl の Lua module は luarocks install + standalone 実行を前提にするか、特定 host process (vdsl-mcp / IDE / user-managed daemon) に embed されることを前提にするか
2. **Application スタイル** — vdsl-mcp は "LocalSingletonApp" (1 PC 1 instance、global state を持つ daemon) なのか、"DevToolLike" (任意 cwd で起動、project ごとに別 instance) なのか、両方サポートするのか
3. **Sync 接合 (必須要件)** — 現実の sync system は **SingleGlobalForSinglePC** (1 host 1 sync DB / 1 work_dir / 1 cloud prefix) で動いている。Top Level 設計で project 抽象を導入するなら、この前提との接合 (sync DB 配置 / cloud namespace / process scope の env 隔離戦略 / per-project sdk lifecycle) が必須要件

上記 3 軸が確定するまで、project-local `.vdsl/` ディレクトリ構造、Global Hub registry、`resolve_project_root` chain といった物理配置仕様は本文書から保留する。確定後に再記述する。

以下 §3〜§7 / §5.5 のうち Layer 1/2 を前提とする箇所も §2 確定までは pending として読む (本文は確定後の再記述まで暫定的に残す)。

## 3. ディレクトリの役割境界 (Layer 1)

> 注: 本節の Layer 1 仕様は §2 確定までは保留状態にある。下記表は再開時の参考扱い。

| Path | 役割 | 例 | git 管理 |
|---|---|---|---|
| `.vdsl/project.toml` | machine-managed メタ (slug / kind / created / schema_version) | — | ✅ |
| `.vdsl/cache/` | manifest hash / transient lookup | — | ❌ |
| `src/` | 自由 Lua: catalog 拡張、自作 Trait、helper、product 固有モジュール | `src/my_catalog.lua`, `src/coding_orch.lua` | ✅ |
| `profiles/` | Profile DSL のみ、宣言型 (`vdsl.profile{}`) | `profiles/zimage_turbo.lua` | ✅ |
| `sweeps/` | 実走 spec (Profile を pod に投げるシナリオ Lua) | `sweeps/qwen_smoketest.lua` | ✅ |
| `notes/` | kickoff / 検討メモ / 思いつき | `notes/kickoff.md` | ✅ |
| `journal.md` | 作業日記 (時系列) | — | ✅ |
| `refs/` | Creative input (人が直接 ls して見る対象) | `refs/inspiration_001.png` | ✅ |
| `final/` | curated PNG 置き場 (init 時は空で scaffold) | `final/hero_v3.png` | ⚠ 任意 |
| `output/` | raw 大量出力 (生成器の素吐き) | `output/run_001/...` | ❌ |

### src / sweeps / profiles の三役 (混乱しやすい)

- **`profiles/`** = pod 環境の宣言 (何の ComfyUI / 何の vLLM / 何の model)
- **`sweeps/`** = 「その profile に対して何を投げるか」の実走 spec
- **`src/`** = 上記いずれにも入らない自由 Lua (catalog 拡張 / 自作 helper / product 固有 module)

迷ったら: 宣言なら profiles、実走なら sweeps、その他は src。

## 4. .gitignore 推奨テンプレ

> 注: §2 確定までは保留状態にある。下記は再開時の参考扱い。

`vdsl_project_init` が project ルートに以下を書き出す想定:

```gitignore
.vdsl/cache/
output/
sweeps/_runs/
# final/  ← 画像が増えたら uncomment、または git-lfs へ
```

`final/` は default で ignore しない (空 scaffold のまま git 管理可)。画像が増えてきた時点で user が判断して uncomment / LFS 化。

## 5. PNG / Profile / Project の所有境界

| 単位 | 所有者 | 持ち運び | 復元元 |
|---|---|---|---|
| **PNG (生成画像)** | vdsl 本体 (lua module) | ✅ 完全独立 (1 枚で recipe + workflow 復元可) | `vdsl.import_png()` |
| **Profile** | vdsl-mcp + project | ⚠ MCP root + credential 必須 | `vdsl_profile_apply` |
| **Project** | (保留 — §2 確定後に再定義) | — | — |

PNG は ComfyUI 正常進化の延長で「画像 1 枚 = self-contained」を保つ。Profile は environment-bound、現状の vdsl-mcp work_dir 配下で運用する。Project 単位の所有境界は §2 の Top Level 設計確定後に定義する。

## 5.5 vdsl 本体 (Lua module) の所在: 保留

vdsl Lua module の package 配置 (luarocks install / vendor / 両方) と version pinning 戦略 (Rockspec dependency / `<ProjectDir>/.vdsl/vendor/`) は、§2 の Top Level 設計 (Lua 実行モデル / Application スタイル) に依存する。実行モデル未決のため本節も **保留**。

過去検討した選択肢 (確定ではない):

- Rockspec dependency declaration (`luarocks install` 経由、project が luarocks 前提で動くケース)
- Vendor (`<ProjectDir>/` 内に固定 source 同梱、hermetic / luarocks 不在環境 / 古い version 凍結)

§2 確定後にどちらを default にするか、または両方をサポートするかを決める。それまでは vdsl 本体 を `~/projects/vdsl-work/vdsl` に clone した tree を `VDSL_WORK_DIR` で指す現運用 (vdsl-mcp 埋め込み Lua が require する経路) を暫定とする。

## 6. MCP root 解決 — 現状の事実

`vdsl-mcp` v0.5.0 / v0.6.0 開発時に `resolve_project_root` (5 段 chain: explicit param / `$VDSL_PROJECT_ROOT` / `$PWD/.vdsl` / Hub registry / symlink) を `domain/project.rs` に実装した経緯があるが、**sync system はこの解決経路を一切呼んでいなかった**。`build_sdk` (`interface/mcp.rs`) は MCP プロセス起動時に `default_work_dir()` (= `VDSL_WORK_DIR` env 単一 source) から 1 回だけ build され、tool call 単位で project root を切り替える経路は無い。chain の側だけ実装しても sync が貫通しない構造亀裂のため、v0.6.0 a8100a9 で chain 実装と Layer 2 registry tool は履歴から削除済 (filter-repo)。

したがって現状の vdsl-mcp は **SingleGlobalForSinglePC** として動作する (1 プロセス 1 work_dir 1 cloud prefix)。複数 project を扱う運用は、MCP プロセスを project ごとに別起動 + 環境変数 (`VDSL_WORK_DIR`) で work_dir を隔離する形でしか実現しない (ただし B2 cloud prefix `vdsl/output` `vdsl/projects` は固定で、project 同士は cloud namespace 上で衝突する)。

§2 の Top Level 設計 (project root 抽象を sync まで貫通させるか / 1 MCP 1 project で割り切るか / sync を library 側に外して MCP を無状態 dispatcher 化するか) が確定した後に、本節の chain 仕様 / 実装パスを再記述する。

## 7. 関連 issue

- `1778017454-16054` — projects/ を repo 外に逃がす案。**§2 Top Level 設計確定後に再開**。v0.6.0 で一度 vdsl-mcp 側に Layer 1/2 を入れたが、sync 未貫通で空 spec と判明し切り戻し済 (vdsl-mcp 側 commit `a8100a9` ベース)。
- `1778017459-16098` — vdsl-starter テンプレ repo の検討。Layer 1 物理仕様確定までは凍結。

## 8. 非対象 (この文書のスコープ外)

- 個別 catalog の物理的 schema (`docs/catalog-spec.md` 領分)
- Profile DSL の field 仕様 (`docs/profile-and-orchestration.md` 領分)
- pod 側の運用フロー (同上)

本文書は **「どこに何が住み、誰が所有し、git 管理するか」** だけを定義する。具体実装の細部は各 docs に委ねる。実行モデル (§2) が未決の現時点では物理配置仕様の一部 (§3 / §4 / §5 Project 行 / §5.5 / §6) は保留状態にある。
