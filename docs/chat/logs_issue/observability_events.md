# AgentCore Observability でイベントが表示されない問題 (2025-10-25)

## 現象
- CloudWatch の Generative AI Observability ダッシュボードで、対象エージェントのスパンは取得できるが「イベントはありません」と表示される。
- 表示されるスパンは `Bedrock AgentCore.ListEvents` のみで、期待しているリクエスト/レスポンス本文（日本語プロンプトなど）が確認できない。

## 調査で分かったこと
- Generative AI Observability のイベント一覧は、内部で `ListEvents` API を呼び出してメモリ上のイベントを引き当てている。citeturn39open0
- `ListEvents` は `memoryId` に加えて `actorId` / `sessionId` で絞り込みを行う仕様で、値が一致しないとイベントは返らない。citeturn38open0
- Agent Runtime 呼び出しでは `runtimeSessionId` が API パス引数として渡される一方、リクエストボディ内の `sessionId` フィールドは省略可能でデフォルトでは送られない。citeturn5open0
- 当該アプリの `create_agent` 実装では、`session_id` / `actor_id` が指定されない場合に `DEFAULT_SESSION_ID="default-session"` と `DEFAULT_ACTOR_ID="default-user"` を使って AgentCore Memory にイベントを書き込む設計になっている（`src/agentcore_hands_on/agent.py:169-207`、`src/agentcore_hands_on/config.py:33-35`）。
- AgentCore Runtime からの実行時には `session_id` / `actor_id` をボディで渡していないため、すべてのイベントが `default-session` / `default-user` に保存され、Observability 側が照会する `runtimeSessionId` とは不一致となる。

## 原因
Runtime から付与される実際のセッション ID / アクター ID を受け取らず、アプリ側が固定値 (`default-session` / `default-user`) で AgentCore Memory にイベントを書き込んでいるため。Observability が `ListEvents` で検索しているセッション条件と保存先が一致せず、結果としてイベントがゼロ件になる。期待しているイベント本文は `medurance_agent` 等の比較対象では一致した ID で保存されているため、そちらでは表示されている。citeturn30open0

## 対応案
1. **Runtime のメタデータを明示的に受け取りメモリに引き渡す**  
   - FastAPI ハンドラで `runtimeSessionId` や `actorId` をヘッダーまたはリクエストボディ／`sessionState` から取得し、`create_agent(session_id=..., actor_id=...)` に渡す。  
   - 実装前に `request.headers` や受信 JSON をロギングして、Runtime がどのキーで値を送っているか確認する。
2. **一時的な検証**  
   - CloudWatch Logs の `/aws/bedrock-agentcore/runtimes/...` ログストリームで `Memory統合有効:` ログを確認し、出力されている `session_id` `actor_id` が `default-session` / `default-user` になっていることを証明する。  
   - 同じ値で `ListEvents` を直接実行するとイベントが取得できることを確認する（AWS CLI 例: `aws bedrock-agentcore list-events --memory-id <ID> --session-id default-session --actor-id default-user`).
3. **修正後の確認**  
   - 修正をデプロイした後、Observability で対象スパンのイベント欄にプロンプト/レスポンス本文が表示されることを確認。  
   - 追加で CloudWatch Logs に `gen_ai.*` イベントが蓄積されることをチェックする。

## 補足
- AgentCore Runtime からは `runtimeSessionId` が必ず渡される仕様のため（InvokeAgentRuntime API 参照）、アプリ側でセッション ID を持たない場合はこの値を利用するのが確実。citeturn5open0
- 観測したスパン属性の `telemetry.extended=true` は拡張テレメトリが有効なことを示しており、ID を揃えればイベント本文も表示されることが比較事例から分かる。citeturn30open0
