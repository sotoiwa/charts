# myliberty

## 概要

LibertyコンテナをStatefulSetとしてデプロイします。アプリケーションはInit ContainerからLibertyコンテナにコピーします。

## リリースの準備作業

### Init Containerのビルド

Init Containerとして使用するイメージの`/config`と`/userhome`に必要なファイルを含めて下さい。Podの起動時に`/config`と`/userhome`の内容をLibertyコンテナの`/config`と`/userhome`にコピーします。

```dockerfile
FROM alpine:3.8
COPY config/* /config/
COPY userhome/* /userhome/
```

### ConfigMap/Secret

アプリケーションが必要とする構成情報はConfigMap/Secretで渡すことができます。`env`ではなく`envFrom`を使っているので、ConfigMap/SecretのKey名がそのまま環境変数名となります。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: common-env
data:
  DB2_PORT: "50000"
  DB2_SERVERNAME: db2
```

ConfigMap/Secretはその名前を`values.yaml`で指定して下さい。

```yaml
secretName: common-env
configMapName: common-env
```

### PersistentVolume

チャートをリリースすると、StatefulSetを使用しているので、`volumeClaimTemplates`の定義に基づいてPersistentVolumeClaimが作成されます。
PersistentVolumeClaimの名前は`liberty-pvc-<サブシステム名>-<番号>`のようになります。ストレージクラス名はサブシステム名になります。

チャートのリリース前あるいはリリース後に、この要件を満たすPersistentVolumeを作成して下さい。`claimRef`を指定することで、特定のPersistentVolumeClaimにのみバインドさせることができます。

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: myliberty-pv-9.188.124.125
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ca
  claimRef:
    namespace: sugi
    name: liberty-pvc-ca-0
  local:
    path: /tmp/ca-prod
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - 9.188.124.125

```

## チャートのリリース

リリース時には必ずリリース名とデプロイ先のNamespaceを指定して下さい。リリース名は`<サブシステム名>-<環境名>`というネーミングに従う必要があります。あまり長い名前にするとエラーになる可能性があります。

### ICPへのログイン

helmクライアントはkubectlの認証情報を使用します。cloudctlコマンドを使ってログインをして下さい。

```
cloudctl login -a https://mycluster.icp:8443 --skip-ssl-validation
```

helmクライアントを一度も使用したことがない場合は、初期化をして下さい。

```
helm init
```

### デバッグ方法

以下のコマンドを実行し、チャートの静的チェックができます。

```
helm lint myliberty
```

実際のリリース前には以下のコマンドを実行し、リリースされるマニフェストを確認することができます。

```
helm install --tls --debug --dry-run --name <リリース名> --namespace <Namespace名> -f <valuefile> myliberty
```

### リリース方法

リリースは以下のコマンドで実行します。valuefileを指定することでデフォルト値を上書きできます。

```
helm install --tls --name <リリース名> --namespace <Namespace名> -f <valuefile> myliberty
```
