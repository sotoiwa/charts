# myliberty

## 概要

LibertyコンテナをStatefulSetとしてデプロイします。アプリケーションはInit ContainerからLibertyコンテナにコピーします。

## リリースの準備作業

### Init Containerのビルド

Init Containerをビルドします。

[sample/build/myliberty-app](./sample/build/myliberty-app)フォルダに例があるので参照して下さい。

Podの起動時に`/config`と`/userhom/ida`の内容をLibertyコンテナの`/config`と`/userhome/ida`にコピーするので、イメージの`/config`と`/userhome/ida`に必要なファイルを含めて下さい。

```dockerfile
FROM alpine:3.8
COPY config/ /config/
COPY userhome/ida/ /userhome/ida/
```

ビルドしてプライベートレジストリにpushします。

```shell
docker build -t mycluster.icp:8500/prod/myliberty-app:0.0.1
docker push mycluster.icp:8500/prod/myliberty-app:0.0.1
```

### Libertyコンテナのビルド

ロケールの変更や追加のフィーチャーの導入をしたLibertyイメージを作成します。

[sample/build/myliberty](./sample/build/myliberty)フォルダに例があるので参照して下さい。


```dockerfile
FROM websphere-liberty:18.0.0.4-javaee8
# Change locale and timezone
USER 0
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    language-pack-ja \
    tzdata \
  && rm -rf /var/lib/apt/lists/* \
  && ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime \
  && dpkg-reconfigure -f noninteractive tzdata
USER 1001
# Install features
RUN /opt/ibm/wlp/bin/installUtility install wmqJmsClient-2.0 --acceptLicense
# Copy libraries
COPY --chown=1001:0 db2jcc* /opt/ibm/wlp/bin/shared/resources/jdbc/db2/
COPY --chown=1001:0 wmq* /opt/ibm/wlp/bin/shared/resources/jms/wmq/
ENV LANG ja_JP.UTF-8
ENV TZ Asia/Tokyo
```

ビルドしてプライベートレジストリにpushします。

```shell
docker build -t mycluster.icp:8500/prod/myliberty:0.0.1
docker push mycluster.icp:8500/prod/myliberty:0.0.1
```

### RoleBindingの作成

Init Containerでカーネルパラメータを変更しているため、Init Containerに`privileged`な権限が必要です。ICPではデフォルトで`privileged`という`privileged`コンテナを作成可能なPodSecurityPolicy定義されており、またこのPodSecurityPolicyを利用可能な`privileged`というClusterRoleが定義されています。このClusterRoleをデプロイするNamespaceの`dafault`のServiceAccountにバインドするRoleBindingを作成します。

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: privileged-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: privileged
subjects:
- kind: ServiceAccount
  name: default
```

### ConfigMap/Secretの作成

アプリケーションが必要とする構成情報はConfigMap/Secretで渡すことができます。StatfulSetのマニフェストでは`env`ではなく`envFrom`を使っているので、ConfigMap/SecretのKey名がそのまま環境変数名となります。Key名には環境変数名を指定してください。

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: common-env
data:
  DB2_PORT: "50000"
  DB2_SERVERNAME: db2
```

チャートのリリース時に作成したConfigMap/Secretの名前を`values.yaml`で指定して下さい。

```yaml
secretName: common-env
configMapName: common-env
```

### PersistentVolume

チャートをリリースすると、StatefulSetを使用しているので、`volumeClaimTemplates`の定義に基づいてPersistentVolumeClaimが作成されます。
PersistentVolumeClaimの名前は`liberty-pvc-<サブシステム名>-<番号>`のようになります。`liberty-pvc`の部分は`values.yaml`の`persistence.name`で指定可能です。ストレージクラス名はリリース名になります。

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
  storageClassName: ca-prod
  claimRef:
    namespace: prod
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

```shell
cloudctl login -a https://mycluster.icp:8443 --skip-ssl-validation
```

helmクライアントを一度も使用したことがない場合は、初期化をして下さい。

```shell
helm init
```

### デバッグ方法

以下のコマンドを実行し、チャートの静的チェックができます。

```shell
helm lint myliberty
```

以下のコマンドを実行し、実際にリリースされるマニフェストを確認することができます。

```shell
helm install --tls --debug --dry-run --name <リリース名> --namespace <Namespace名> -f <valuefile> myliberty
```

### リリース方法

リリースは以下のコマンドで実行します。valuefileを指定することでデフォルト値を上書きできます。

```shell
helm install --tls --name <リリース名> --namespace <Namespace名> -f <valuefile> myliberty
```
