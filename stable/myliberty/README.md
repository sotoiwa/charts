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

Init Containerでカーネルパラメータを変更しているため、Init Containerに`privileged`な権限が必要です。ICPではデフォルトで`privileged`という`privileged`コンテナを作成可能なPodSecurityPolicyが定義されており、またこのPodSecurityPolicyを利用可能な`privileged`というClusterRoleが定義されています。このClusterRoleをデプロイするNamespaceの`dafault`のServiceAccountにバインドするRoleBindingを作成します。

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

チャートをリリースすると、StatefulSetの`volumeClaimTemplates`の定義に基づいてPersistentVolumeClaimが作成されます。
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

## 実際のマニフェスト例

以下のようなマニフェストにレンダリングされます。

```yaml
# Source: myliberty/templates/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ca
  labels:
    app: ca
    chart: myliberty-0.0.1
    release: ca-test
    heritage: Tiller
spec:
  serviceName: ca
  updateStrategy:
    type: OnDelete

  selector:
    matchLabels:
      app: ca
  replicas: 1
  template:
    metadata:
      labels:
        app: ca
        chart: myliberty-0.0.1
        release: ca-test
        heritage: Tiller
    spec:
      restartPolicy: Always
      dnsPolicy: ClusterFirst
      terminationGracePeriodSeconds: 30
      hostAliases:
      {}

      initContainers:
      - name: app
        image: "mycluster.icp:8500/prod/myliberty-app:0.0.1"
        imagePullPolicy: Always
        command:
        - sh
        - -c
        - |
          cp -rp /config/* /mnt/config/
          cp -rp /userhome/ida/* /mnt/userhome/ida/
          chown -R 1001:0 /mnt/config
          chown -R 1001:0 /mnt/userhome/ida
          sysctl -w net.core.somaxconn=5000
        securityContext:
          privileged: true
        volumeMounts:
        - name: config-volume
          mountPath: /mnt/config
        - name: ida-volume
          mountPath: /mnt/userhome/ida
      containers:
      - name: liberty
        image: "mycluster.icp:8500/prod/myliberty:18.0.0.4"
        imagePullPolicy: Always
        ports:
        - containerPort: 9080
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /sample/index.html
            port: 9080
          initialDelaySeconds: 180
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1

        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /sample/index.html
            port: 9080
          initialDelaySeconds: 10
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 1

        env:
        - name: LICENSE
          value: "accept"
        - name : WLP_SKIP_UMASK
          value: "true"
        - name: WLP_LOGGING_CONSOLE_FORMAT
          value: basic
        - name: WLP_LOGGING_CONSOLE_LOGLEVEL
          value: info
        - name: WLP_LOGGING_CONSOLE_SOURCE
          value: message
        - name: MP_METRICS_TAGS
          value: "app=ca-test"
        - name: JVM_ARGS
          value:
        - name: NODENAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        envFrom:
        - configMapRef:
            name: "common-env"
        - secretRef:
            name: "common-env"
        resources:
          {}

        volumeMounts:
        - name: config-volume
          mountPath: /config
        - name: ida-volume
          mountPath: /userhome/ida
        - name: liberty-pvc
          mountPath: /logs
          subPath: logs
        - name: liberty-pvc
          mountPath: /Local/core/wlp
          subPath: dump
        - name: liberty-pvc
          mountPath: /Local/uservar000/ida/log
          subPath: applogs
      volumes:
      - name: config-volume
        emptyDir: {}
      - name: ida-volume
        emptyDir: {}
  volumeClaimTemplates:
  - metadata:
      name: "liberty-pvc"
    spec:
      storageClassName: ca-test
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: "1Gi"

---
# Source: myliberty/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: ca-np
  labels:
    app: ca
    chart: myliberty-0.0.1
    release: ca-test
    heritage: Tiller
spec:
  type: ClusterIP
  selector:
    app: ca
  ports:
  - port: 9080
    targetPort: 9080
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  name: ca
  labels:
    chart: myliberty-0.0.1
    release: ca-test
    heritage: Tiller
spec:
  type: ClusterIP
  clusterIP: None
  selector:
    app: ca
  ports:
  - port: 9080
    targetPort: 9080
    protocol: TCP

---
# Source: myliberty/templates/ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: ca
  annotations:
    # ingress.kubernetes.io/rewrite-target: /
    ingress.kubernetes.io/ssl-redirect: "false"
    ingress.kubernetes.io/affinity: "cookie"
    ingress.kubernetes.io/session-cookie-name: "route-ca"
    ingress.kubernetes.io/session-cookie-hash: "sha1"
    ingress.kubernetes.io/server-snippet: |-
      location /sample/admin {
          deny all;
      }
  labels:
    app: ca
    chart: myliberty-0.0.1
    release: ca-test
    heritage: Tiller
spec:
  rules:
  - host:
    http:
      paths:
      - path: /sample
        backend:
          serviceName: ca
          servicePort: 9080
```