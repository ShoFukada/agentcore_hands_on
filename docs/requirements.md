# エージェント要件

## AgentCore コンポーネント

### Agent Runtime
- Strands Agents フレームワークを使用してエージェントをデプロイ
- ECR にコンテナイメージをプッシュして実行
- 自動スケーリング対応のサーバーレス実行環境

### Memory
- セッション間での会話履歴を管理
- 1つのセッション内でコンテキストを維持する短期メモリ
- エージェントの状態とデータの永続化ストレージ

### Code Interpreter
- 動的なコード実行のための Python 実行環境
- JavaScript ベースの操作のための TypeScript 実行環境
- セキュアなコード実行のためのサンドボックス環境
- データ分析と処理タスクのサポート

### Browser
- Web 自動化のためのヘッドレスブラウザ環境
- Web スクレイピングとページ操作のサポート
- Web ページからの情報抽出とナビゲーション

### Gateway + Identity
- Gateway を通じて Tavily API に接続
- Identity で API 認証情報を安全に管理
- Web リサーチ機能を有効化
- OAuth2/API キー認証のサポート

### Observability
- AWS X-Ray による分散トレーシング
- CloudWatch Transaction Search でのスパン収集とインデックス化
- CloudWatch Logs へのトレースデータ自動送信
- エージェント実行フローの可視化とデバッグ
- パフォーマンスメトリクスの監視
- エラートレースとボトルネック分析


## 検討要件
### RAG (Retrieval-Augmented Generation)
- Amazon Bedrock Knowledge Base を使用
- エージェントから直接 Knowledge Base にアクセス
- S3 にドキュメントを配置してベクトル化
- 意味検索による文書検索機能
