# State Boundaries

vdsl 関連の成果物・状態がどこに住み、誰が所有し、git 管理するかしないかの境界線を 1 箇所に固定する文書。実装 (vdsl Lua / vdsl-mcp / luarocks 配布物) の所在判断と、user の運用 (project の置き場 / .gitignore) の両方が、この文書の境界に従う。

## 1. 三つの軸

| 軸 | 役割 | 例 |
|---|---|---|
| **portable** | 1 単位だけで自己完結し、外に持ち出して再生できる | PNG (recipe + workflow tEXt) |
| **environment-bound** | credentials / endpoint / pod state に紐付く | Profile (B2 routes, env, custom_nodes) |
| **workflow-state** | その project の作業履歴 / 中間成果 / 自由 Lua | notes / journal / sweeps / src |

vdsl 本体 (Lua module) は portable 層を扱う。MCP (vdsl-mcp) は environment-bound 層と workflow-state 層を扱う。

## 2. 二層モデル

```
[Layer 1] Project-local <ProjectDir>/.vdsl/    ← 基本運用 (.git 同等)
[Layer 2] Global Hub    ~/.vdsl/                ← Fat-IDE 統合 view
```

### Layer 1: Project-local

各 product / repo / 作業 unit ごとに、その directory 直下に `.vdsl/` を置く。`.git` と同じく薄いメタ層で、成果物本体は ProjectDir 直下に並ぶ。

```
<ProjectDir>/
 ├─ .vdsl/
 │   ├─ project.toml          # slug, kind, created, schema_version, hub binding
 │   └─ cache/                # gitignored (manifest hash, transient lookup)
 ├─ src/                      # 自由 Lua (catalog 拡張 / 自作 Trait / helper)
 ├─ profiles/<name>.lua       # Profile DSL (宣言型、vdsl.profile{})
 ├─ sweeps/                   # 実走 spec (Profile を pod に投げるシナリオ)
 ├─ notes/                    # メモ / kickoff / 検討
 ├─ journal.md                # 作業日記
 ├─ refs/                     # Creative input (参照画像 / 引用)
 ├─ final/                    # curated PNG (空で scaffold、画像置く想定)
 └─ output/                   # raw 大量出力 (gitignored)
```

`<ProjectDir>` 自体は git 管理することを推奨 (Lua spec が成果物の核なので)。`vdsl_project_init` は `<ProjectDir>/.vdsl/project.toml` と上記 dir 構造を生成する。

### Layer 2: Global Hub

複数 project を横断する index と共有領域。Fat IDE の "Recent Projects" 相当。

```
~/.vdsl/
 ├─ registry.json             # 登録済 project の path index
 │   [{ "slug": "qwen-coding-orch",
 │      "path": "/Users/.../coding-orch",
 │      "kind": "vllm-product",
 │      "registered_at": ...,
 │      "last_used": ... }]
 ├─ projects/                 # (任意) symlink farm: slug → ProjectDir/.vdsl
 │   └─ qwen-coding-orch -> /Users/.../coding-orch/.vdsl
 └─ shared/                   # cross-project 共有
     ├─ catalogs/             # 自作 catalog (project またぎで使うもの)
     └─ assets/               # 共有 LoRA list / 参照素材
```

Hub は単独で何かを「持つ」のではなく、Layer 1 への索引と共有プール。Hub を消しても各 ProjectDir/.vdsl/ は無事。

## 3. ディレクトリの役割境界 (Layer 1)

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

`vdsl_project_init` が project ルートに以下を書き出す:

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
| **Project** | project owner (user) + Hub | ⚠ ProjectDir + Hub registry | `vdsl_project_init` / `vdsl_project_register` |

PNG は ComfyUI 正常進化の延長で「画像 1 枚 = self-contained」を保つ。Profile / Project は state を持つので Layer 1 (ProjectDir) と Layer 2 (Hub) の組で初めて再生可能。

## 5.5 vdsl 本体 (Lua module) の所在

vdsl の Lua module 本体は luarocks の標準 install tree に住む (`~/.luarocks/share/lua/5.x/vdsl/`)。`~/.vdsl/` は user state hub 専用で、本体コードは置かない。これにより本体 upgrade と user state の lifecycle が独立する (`luarocks install vdsl` を打っても `~/.vdsl/registry.json` は壊れない)。

### Version pinning は project-local で

vdsl の version を project ごとに pin したい場合、**`<ProjectDir>/` の中で完結させる**。`~/.vdsl/` (user-global) には置かない。

| 手段 | 場所 | 想定ユース |
|---|---|---|
| Rockspec dependency (推奨) | `<ProjectDir>/<project>-X.Y.Z-1.rockspec` で `vdsl >= X.Y` を declare、`luarocks make` で install | project が luarocks 前提で動くケース、CI で再現可 |
| Vendor (固定 source 同梱) | `<ProjectDir>/.vdsl/vendor/lua/vdsl/` に vdsl tree を置き、`package.path` を project-local に shim | 完全 hermetic にしたい / luarocks 不在環境 / 古い version を凍結したい |

vendoring を選ぶ場合の規約:

- 物理位置は `<ProjectDir>/.vdsl/vendor/lua/vdsl/...` (薄メタの中、cache と並列)
- `<ProjectDir>/.vdsl/vendor/` は **gitignore しない** (project が再現可能であることを優先、size 増は許容)
- shim 例: `lua -e "package.path='./.vdsl/vendor/lua/?.lua;./.vdsl/vendor/lua/?/init.lua;'..package.path" sweeps/run.lua`

`~/.vdsl/shared/` は cross-project 共有 catalog / asset 用であり、library code の vendor 先ではない。境界を混ぜない。

## 6. MCP root 解決順 (resolve_project_root)

`vdsl-mcp` の root 解決は以下の優先順:

1. explicit param (`name=` or `root=`)
2. `$VDSL_PROJECT_ROOT` (env、power user override)
3. `$PWD/.vdsl` があれば → そのまま採用 (auto-detect、IDE-friendly)
4. `~/.vdsl/registry.json` から slug 解決 (Hub 経由)
5. `~/.vdsl/projects/<slug>` (symlink fallback)

旧 default (`$VDSL_WORK_DIR/projects` / `~/projects/vdsl-work/vdsl/projects`) は env で互換維持し、新 default は Layer 1/2 モデルに切替える (issue 1778017454-16054 の核)。

## 7. 関連 issue

- `1778017454-16054` — projects/ を repo 外に逃がす (本文書に基づき実装)
- `1778017459-16098` — vdsl-starter テンプレ repo の検討 (Layer 1 ProjectDir の git template として)

## 8. 非対象 (この文書のスコープ外)

- 個別 catalog の物理的 schema (`docs/catalog-spec.md` 領分)
- Profile DSL の field 仕様 (`docs/profile-and-orchestration.md` 領分)
- pod 側の運用フロー (同上)

本文書は **「どこに何が住み、誰が所有し、git 管理するか」** だけを定義する。具体実装の細部は各 docs に委ねる。
