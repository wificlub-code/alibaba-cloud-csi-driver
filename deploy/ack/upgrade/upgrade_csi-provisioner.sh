#!/bin/bash

## Usage
## Append image tag which is expect.
## sh upgrade_csi-provisioner.sh v1.14.8.38-fe611ad1-aliyun


if [ "$1" = "" ]; then
  echo "Please input the expect csi provisioner version... "
fi
imageVersion=$1

echo `date`" Start to Upgrade CSI Provisioner to $imageVersion ..."

masterCount=`kubectl get node | grep master |grep -v grep | wc -l`
volumeDefineStr=""
volumeMountStr=""
if [ "$masterCount" -eq "0" ]; then
  volumeDefineStr="        - name: addon-token\n          secret:\n            defaultMode: 420\n            items:\n            - key: addon.token.config\n              path: token-config\n            secretName: addon.csi.token"
  volumeMountStr="            - mountPath: \/var\/addon\n              name: addon-token\n              readOnly: true"
fi


# new deploy template file
# if any changes, just update here and replace image value
cat > .aliyun-csi-provisioner-dedicate.yaml << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-available
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: available
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-essd
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: cloud_essd
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-ssd
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: cloud_ssd
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-efficiency
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: cloud_efficiency
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-topology
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: available
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: csi-provisioner
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: csi-provisioner
  replicas: 2
  template:
    metadata:
      labels:
        app: csi-provisioner
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            preference:
              matchExpressions:
              - key: node-role.kubernetes.io/master
                operator: Exists
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: type
                operator: NotIn
                values:
                - virtual-kubelet
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - csi-provisioner
              topologyKey: "kubernetes.io/hostname"
      tolerations:
      - effect: NoSchedule
        operator: Exists
        key: node-role.kubernetes.io/master
      - effect: NoSchedule
        operator: Exists
        key: node.cloudprovider.kubernetes.io/uninitialized
      priorityClassName: system-node-critical
      serviceAccount: admin
      hostNetwork: true
      containers:
        - name: external-disk-provisioner
          image: csi-image-prefix/acs/csi-provisioner:v1.6.0-b6f763a43-aliyun
          args:
            - "--provisioner=diskplugin.csi.alibabacloud.com"
            - "--csi-address=\$(ADDRESS)"
            - "--feature-gates=Topology=True"
            - "--volume-name-prefix=disk"
            - "--strict-topology=true"
            - "--timeout=150s"
            - "--enable-leader-election=true"
            - "--leader-election-type=leases"
            - "--retry-interval-start=500ms"
            - "--v=5"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
        - name: external-disk-attacher
          image: csi-image-prefix/acs/csi-attacher:v2.1.0
          args:
            - "--v=5"
            - "--csi-address=\$(ADDRESS)"
            - "--leader-election=true"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
        - name: external-disk-resizer
          image: csi-image-prefix/acs/csi-resizer:v0.3.0
          args:
            - "--v=5"
            - "--csi-address=\$(ADDRESS)"
            - "--leader-election"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
        - name: external-nas-provisioner
          image: csi-image-prefix/acs/csi-provisioner:v1.4.0-aliyun
          args:
            - "--provisioner=nasplugin.csi.alibabacloud.com"
            - "--csi-address=\$(ADDRESS)"
            - "--volume-name-prefix=nas"
            - "--timeout=150s"
            - "--enable-leader-election=true"
            - "--leader-election-type=leases"
            - "--retry-interval-start=500ms"
            - "--v=5"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/nasplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: nas-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/nasplugin.csi.alibabacloud.com
        - name: external-csi-snapshotter
          image: csi-image-prefix/acs/csi-snapshotter:v3.0.2-1038b92d8-aliyun
          args:
            - "--v=5"
            - "--csi-address=\$(ADDRESS)"
            - "--leader-election=true"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          imagePullPolicy: Always
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /csi
        - name: external-snapshot-controller
          image: csi-image-prefix/acs/snapshot-controller:v3.0.2-1038b92d8-aliyun
          args:
            - "--v=5"
            - "--leader-election=true"
          imagePullPolicy: Always
        - name: csi-provisioner
          securityContext:
            privileged: true
            capabilities:
              add: ["SYS_ADMIN"]
            allowPrivilegeEscalation: true
          image: csi-image-prefix/acs/csi-plugin:csi-image-version
          imagePullPolicy: "Always"
          args:
            - "--endpoint=\$(CSI_ENDPOINT)"
            - "--v=2"
            - "--driver=nas,disk"
          env:
            - name: CSI_ENDPOINT
              value: unix://var/lib/kubelet/csi-provisioner/driverplugin.csi.alibabacloud.com-replace/csi.sock
            - name: MAX_VOLUMES_PERNODE
              value: "15"
            - name: SERVICE_TYPE
              value: "provisioner"
          livenessProbe:
            httpGet:
              path: /healthz
              port: healthz
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 5
          ports:
            - name: healthz
              containerPort: 11270
              protocol: TCP
          volumeMounts:
            - name: host-dev
              mountPath: /dev
              mountPropagation: "HostToContainer"
            - name: host-log
              mountPath: /var/log/
            - name: etc
              mountPath: /host/etc
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
            - name: nas-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/nasplugin.csi.alibabacloud.com
          resources:
            limits:
              cpu: 1000m
              memory: 1000Mi
            requests:
              cpu: 100m
              memory: 100Mi
      volumes:
        - name: disk-provisioner-dir
          emptyDir: {}
        - name: nas-provisioner-dir
          emptyDir: {}
        - name: host-log
          hostPath:
            path: /var/log/
        - name: host-dev
          hostPath:
            path: /dev
        - name: etc
          hostPath:
            path: /etc
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.3.0
    api-approved.kubernetes.io: "https://github.com/kubernetes-csi/external-snapshotter/pull/139"
  creationTimestamp: null
  name: volumesnapshotclasses.snapshot.storage.k8s.io
spec:
  group: snapshot.storage.k8s.io
  names:
    kind: VolumeSnapshotClass
    listKind: VolumeSnapshotClassList
    plural: volumesnapshotclasses
    singular: volumesnapshotclass
  scope: Cluster
  versions:
  - additionalPrinterColumns:
    - jsonPath: .driver
      name: Driver
      type: string
    - description: Determines whether a VolumeSnapshotContent created through the
        VolumeSnapshotClass should be deleted when its bound VolumeSnapshot is deleted.
      jsonPath: .deletionPolicy
      name: DeletionPolicy
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: Age
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: VolumeSnapshotClass specifies parameters that a underlying storage
          system uses when creating a volume snapshot. A specific VolumeSnapshotClass
          is used by specifying its name in a VolumeSnapshot object. VolumeSnapshotClasses
          are non-namespaced
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          deletionPolicy:
            description: deletionPolicy determines whether a VolumeSnapshotContent
              created through the VolumeSnapshotClass should be deleted when its bound
              VolumeSnapshot is deleted. Supported values are "Retain" and "Delete".
              "Retain" means that the VolumeSnapshotContent and its physical snapshot
              on underlying storage system are kept. "Delete" means that the VolumeSnapshotContent
              and its physical snapshot on underlying storage system are deleted.
              Required.
            enum:
            - Delete
            - Retain
            type: string
          driver:
            description: driver is the name of the storage driver that handles this
              VolumeSnapshotClass. Required.
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          parameters:
            additionalProperties:
              type: string
            description: parameters is a key-value map with storage driver specific
              parameters for creating snapshots. These values are opaque to Kubernetes.
            type: object
        required:
        - deletionPolicy
        - driver
        type: object
    served: true
    storage: true
    subresources: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.3.0
    api-approved.kubernetes.io: "https://github.com/kubernetes-csi/external-snapshotter/pull/139"
  creationTimestamp: null
  name: volumesnapshotcontents.snapshot.storage.k8s.io
spec:
  group: snapshot.storage.k8s.io
  names:
    kind: VolumeSnapshotContent
    listKind: VolumeSnapshotContentList
    plural: volumesnapshotcontents
    singular: volumesnapshotcontent
  scope: Cluster
  versions:
  - additionalPrinterColumns:
    - description: Indicates if a snapshot is ready to be used to restore a volume.
      jsonPath: .status.readyToUse
      name: ReadyToUse
      type: boolean
    - description: Represents the complete size of the snapshot in bytes
      jsonPath: .status.restoreSize
      name: RestoreSize
      type: integer
    - description: Determines whether this VolumeSnapshotContent and its physical
        snapshot on the underlying storage system should be deleted when its bound
        VolumeSnapshot is deleted.
      jsonPath: .spec.deletionPolicy
      name: DeletionPolicy
      type: string
    - description: Name of the CSI driver used to create the physical snapshot on
        the underlying storage system.
      jsonPath: .spec.driver
      name: Driver
      type: string
    - description: Name of the VolumeSnapshotClass to which this snapshot belongs.
      jsonPath: .spec.volumeSnapshotClassName
      name: VolumeSnapshotClass
      type: string
    - description: Name of the VolumeSnapshot object to which this VolumeSnapshotContent
        object is bound.
      jsonPath: .spec.volumeSnapshotRef.name
      name: VolumeSnapshot
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: Age
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: VolumeSnapshotContent represents the actual "on-disk" snapshot
          object in the underlying storage system
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          spec:
            description: spec defines properties of a VolumeSnapshotContent created
              by the underlying storage system. Required.
            properties:
              deletionPolicy:
                description: deletionPolicy determines whether this VolumeSnapshotContent
                  and its physical snapshot on the underlying storage system should
                  be deleted when its bound VolumeSnapshot is deleted. Supported values
                  are "Retain" and "Delete". "Retain" means that the VolumeSnapshotContent
                  and its physical snapshot on underlying storage system are kept.
                  "Delete" means that the VolumeSnapshotContent and its physical snapshot
                  on underlying storage system are deleted. In dynamic snapshot creation
                  case, this field will be filled in with the "DeletionPolicy" field
                  defined in the VolumeSnapshotClass the VolumeSnapshot refers to.
                  For pre-existing snapshots, users MUST specify this field when creating
                  the VolumeSnapshotContent object. Required.
                enum:
                - Delete
                - Retain
                type: string
              driver:
                description: driver is the name of the CSI driver used to create the
                  physical snapshot on the underlying storage system. This MUST be
                  the same as the name returned by the CSI GetPluginName() call for
                  that driver. Required.
                type: string
              source:
                description: source specifies from where a snapshot will be created.
                  This field is immutable after creation. Required.
                properties:
                  snapshotHandle:
                    description: snapshotHandle specifies the CSI "snapshot_id" of
                      a pre-existing snapshot on the underlying storage system. This
                      field is immutable.
                    type: string
                  volumeHandle:
                    description: volumeHandle specifies the CSI "volume_id" of the
                      volume from which a snapshot should be dynamically taken from.
                      This field is immutable.
                    type: string
                type: object
              volumeSnapshotClassName:
                description: name of the VolumeSnapshotClass to which this snapshot
                  belongs.
                type: string
              volumeSnapshotRef:
                description: volumeSnapshotRef specifies the VolumeSnapshot object
                  to which this VolumeSnapshotContent object is bound. VolumeSnapshot.Spec.VolumeSnapshotContentName
                  field must reference to this VolumeSnapshotContent name for the
                  bidirectional binding to be valid. For a pre-existing VolumeSnapshotContent
                  object, name and namespace of the VolumeSnapshot object MUST be
                  provided for binding to happen. This field is immutable after creation.
                  Required.
                properties:
                  apiVersion:
                    description: API version of the referent.
                    type: string
                  fieldPath:
                    description: 'If referring to a piece of an object instead of
                      an entire object, this string should contain a valid JSON/Go
                      field access statement, such as desiredState.manifest.containers[2].
                      For example, if the object reference is to a container within
                      a pod, this would take on a value like: "spec.containers{name}"
                      (where "name" refers to the name of the container that triggered
                      the event) or if no container name is specified "spec.containers[2]"
                      (container with index 2 in this pod). This syntax is chosen
                      only to have some well-defined way of referencing a part of
                      an object. TODO: this design is not final and this field is
                      subject to change in the future.'
                    type: string
                  kind:
                    description: 'Kind of the referent. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                    type: string
                  name:
                    description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names'
                    type: string
                  namespace:
                    description: 'Namespace of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/'
                    type: string
                  resourceVersion:
                    description: 'Specific resourceVersion to which this reference
                      is made, if any. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency'
                    type: string
                  uid:
                    description: 'UID of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids'
                    type: string
                type: object
            required:
            - deletionPolicy
            - driver
            - source
            - volumeSnapshotRef
            type: object
          status:
            description: status represents the current information of a snapshot.
            properties:
              creationTime:
                description: creationTime is the timestamp when the point-in-time
                  snapshot is taken by the underlying storage system. In dynamic snapshot
                  creation case, this field will be filled in with the "creation_time"
                  value returned from CSI "CreateSnapshotRequest" gRPC call. For a
                  pre-existing snapshot, this field will be filled with the "creation_time"
                  value returned from the CSI "ListSnapshots" gRPC call if the driver
                  supports it. If not specified, it indicates the creation time is
                  unknown. The format of this field is a Unix nanoseconds time encoded
                  as an int64. On Unix, the command `date +%s%N` returns the current
                  time in nanoseconds since 1970-01-01 00:00:00 UTC.
                format: int64
                type: integer
              error:
                description: error is the latest observed error during snapshot creation,
                  if any.
                properties:
                  message:
                    description: 'message is a string detailing the encountered error
                      during snapshot creation if specified. NOTE: message may be
                      logged, and it should not contain sensitive information.'
                    type: string
                  time:
                    description: time is the timestamp when the error was encountered.
                    format: date-time
                    type: string
                type: object
              readyToUse:
                description: readyToUse indicates if a snapshot is ready to be used
                  to restore a volume. In dynamic snapshot creation case, this field
                  will be filled in with the "ready_to_use" value returned from CSI
                  "CreateSnapshotRequest" gRPC call. For a pre-existing snapshot,
                  this field will be filled with the "ready_to_use" value returned
                  from the CSI "ListSnapshots" gRPC call if the driver supports it,
                  otherwise, this field will be set to "True". If not specified, it
                  means the readiness of a snapshot is unknown.
                type: boolean
              restoreSize:
                description: restoreSize represents the complete size of the snapshot
                  in bytes. In dynamic snapshot creation case, this field will be
                  filled in with the "size_bytes" value returned from CSI "CreateSnapshotRequest"
                  gRPC call. For a pre-existing snapshot, this field will be filled
                  with the "size_bytes" value returned from the CSI "ListSnapshots"
                  gRPC call if the driver supports it. When restoring a volume from
                  this snapshot, the size of the volume MUST NOT be smaller than the
                  restoreSize if it is specified, otherwise the restoration will fail.
                  If not specified, it indicates that the size is unknown.
                format: int64
                minimum: 0
                type: integer
              snapshotHandle:
                description: snapshotHandle is the CSI "snapshot_id" of a snapshot
                  on the underlying storage system. If not specified, it indicates
                  that dynamic snapshot creation has either failed or it is still
                  in progress.
                type: string
            type: object
        required:
        - spec
        type: object
    served: true
    storage: true
    subresources:
      status: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.3.0
    api-approved.kubernetes.io: "https://github.com/kubernetes-csi/external-snapshotter/pull/139"
  creationTimestamp: null
  name: volumesnapshots.snapshot.storage.k8s.io
spec:
  group: snapshot.storage.k8s.io
  names:
    kind: VolumeSnapshot
    listKind: VolumeSnapshotList
    plural: volumesnapshots
    singular: volumesnapshot
  scope: Namespaced
  versions:
  - additionalPrinterColumns:
    - description: Indicates if a snapshot is ready to be used to restore a volume.
      jsonPath: .status.readyToUse
      name: ReadyToUse
      type: boolean
    - description: Name of the source PVC from where a dynamically taken snapshot
        will be created.
      jsonPath: .spec.source.persistentVolumeClaimName
      name: SourcePVC
      type: string
    - description: Name of the VolumeSnapshotContent which represents a pre-provisioned
        snapshot.
      jsonPath: .spec.source.volumeSnapshotContentName
      name: SourceSnapshotContent
      type: string
    - description: Represents the complete size of the snapshot.
      jsonPath: .status.restoreSize
      name: RestoreSize
      type: string
    - description: The name of the VolumeSnapshotClass requested by the VolumeSnapshot.
      jsonPath: .spec.volumeSnapshotClassName
      name: SnapshotClass
      type: string
    - description: The name of the VolumeSnapshotContent to which this VolumeSnapshot
        is bound.
      jsonPath: .status.boundVolumeSnapshotContentName
      name: SnapshotContent
      type: string
    - description: Timestamp when the point-in-time snapshot is taken by the underlying
        storage system.
      jsonPath: .status.creationTime
      name: CreationTime
      type: date
    - jsonPath: .metadata.creationTimestamp
      name: Age
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: VolumeSnapshot is a user request for either creating a point-in-time
          snapshot of a persistent volume, or binding to a pre-existing snapshot.
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          spec:
            description: 'spec defines the desired characteristics of a snapshot requested
              by a user. More info: https://kubernetes.io/docs/concepts/storage/volume-snapshots#volumesnapshots
              Required.'
            properties:
              source:
                description: source specifies where a snapshot will be created from.
                  This field is immutable after creation. Required.
                properties:
                  persistentVolumeClaimName:
                    description: persistentVolumeClaimName specifies the name of the
                      PersistentVolumeClaim object in the same namespace as the VolumeSnapshot
                      object where the snapshot should be dynamically taken from.
                      This field is immutable.
                    type: string
                  volumeSnapshotContentName:
                    description: volumeSnapshotContentName specifies the name of a
                      pre-existing VolumeSnapshotContent object. This field is immutable.
                    type: string
                type: object
              volumeSnapshotClassName:
                description: 'volumeSnapshotClassName is the name of the VolumeSnapshotClass
                  requested by the VolumeSnapshot. If not specified, the default snapshot
                  class will be used if one exists. If not specified, and there is
                  no default snapshot class, dynamic snapshot creation will fail.
                  Empty string is not allowed for this field. TODO(xiangqian): a webhook
                  validation on empty string. More info: https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes'
                type: string
            required:
            - source
            type: object
          status:
            description: 'status represents the current information of a snapshot.
              NOTE: status can be modified by sources other than system controllers,
              and must not be depended upon for accuracy. Controllers should only
              use information from the VolumeSnapshotContent object after verifying
              that the binding is accurate and complete.'
            properties:
              boundVolumeSnapshotContentName:
                description: 'boundVolumeSnapshotContentName represents the name of
                  the VolumeSnapshotContent object to which the VolumeSnapshot object
                  is bound. If not specified, it indicates that the VolumeSnapshot
                  object has not been successfully bound to a VolumeSnapshotContent
                  object yet. NOTE: Specified boundVolumeSnapshotContentName alone
                  does not mean binding       is valid. Controllers MUST always verify
                  bidirectional binding between       VolumeSnapshot and VolumeSnapshotContent
                  to avoid possible security issues.'
                type: string
              creationTime:
                description: creationTime is the timestamp when the point-in-time
                  snapshot is taken by the underlying storage system. In dynamic snapshot
                  creation case, this field will be filled in with the "creation_time"
                  value returned from CSI "CreateSnapshotRequest" gRPC call. For a
                  pre-existing snapshot, this field will be filled with the "creation_time"
                  value returned from the CSI "ListSnapshots" gRPC call if the driver
                  supports it. If not specified, it indicates that the creation time
                  of the snapshot is unknown.
                format: date-time
                type: string
              error:
                description: error is the last observed error during snapshot creation,
                  if any. This field could be helpful to upper level controllers(i.e.,
                  application controller) to decide whether they should continue on
                  waiting for the snapshot to be created based on the type of error
                  reported.
                properties:
                  message:
                    description: 'message is a string detailing the encountered error
                      during snapshot creation if specified. NOTE: message may be
                      logged, and it should not contain sensitive information.'
                    type: string
                  time:
                    description: time is the timestamp when the error was encountered.
                    format: date-time
                    type: string
                type: object
              readyToUse:
                description: readyToUse indicates if a snapshot is ready to be used
                  to restore a volume. In dynamic snapshot creation case, this field
                  will be filled in with the "ready_to_use" value returned from CSI
                  "CreateSnapshotRequest" gRPC call. For a pre-existing snapshot,
                  this field will be filled with the "ready_to_use" value returned
                  from the CSI "ListSnapshots" gRPC call if the driver supports it,
                  otherwise, this field will be set to "True". If not specified, it
                  means the readiness of a snapshot is unknown.
                type: boolean
              restoreSize:
                type: string
                description: restoreSize represents the complete size of the snapshot
                  in bytes. In dynamic snapshot creation case, this field will be
                  filled in with the "size_bytes" value returned from CSI "CreateSnapshotRequest"
                  gRPC call. For a pre-existing snapshot, this field will be filled
                  with the "size_bytes" value returned from the CSI "ListSnapshots"
                  gRPC call if the driver supports it. When restoring a volume from
                  this snapshot, the size of the volume MUST NOT be smaller than the
                  restoreSize if it is specified, otherwise the restoration will fail.
                  If not specified, it indicates that the size is unknown.
                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                x-kubernetes-int-or-string: true
            type: object
        required:
        - spec
        type: object
    served: true
    storage: true
    subresources:
      status: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
EOF

cat > .aliyun-csi-provisioner-managed.yaml << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-available
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: available
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-essd
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: cloud_essd
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-ssd
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: cloud_ssd
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-efficiency
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: cloud_efficiency
reclaimPolicy: Delete
allowVolumeExpansion: true
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
   name: alicloud-disk-topology
provisioner: diskplugin.csi.alibabacloud.com
parameters:
    type: available
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: csi-provisioner
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: csi-provisioner
  replicas: 2
  template:
    metadata:
      labels:
        app: csi-provisioner
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            preference:
              matchExpressions:
              - key: node-role.kubernetes.io/master
                operator: Exists
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: type
                operator: NotIn
                values:
                - virtual-kubelet
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - csi-provisioner
              topologyKey: "kubernetes.io/hostname"
      tolerations:
      - effect: NoSchedule
        operator: Exists
        key: node-role.kubernetes.io/master
      - effect: NoSchedule
        operator: Exists
        key: node.cloudprovider.kubernetes.io/uninitialized
      priorityClassName: system-node-critical
      serviceAccount: admin
      hostNetwork: true
      containers:
        - name: external-disk-provisioner
          image: csi-image-prefix/acs/csi-provisioner:v1.6.0-b6f763a43-aliyun
          args:
            - "--provisioner=diskplugin.csi.alibabacloud.com"
            - "--csi-address=\$(ADDRESS)"
            - "--feature-gates=Topology=True"
            - "--volume-name-prefix=disk"
            - "--strict-topology=true"
            - "--timeout=150s"
            - "--enable-leader-election=true"
            - "--leader-election-type=leases"
            - "--retry-interval-start=500ms"
            - "--v=5"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
        - name: external-disk-attacher
          image: csi-image-prefix/acs/csi-attacher:v2.1.0
          args:
            - "--v=5"
            - "--csi-address=\$(ADDRESS)"
            - "--leader-election=true"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
        - name: external-disk-resizer
          image: csi-image-prefix/acs/csi-resizer:v0.3.0
          args:
            - "--v=5"
            - "--csi-address=\$(ADDRESS)"
            - "--leader-election"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
        - name: external-nas-provisioner
          image: csi-image-prefix/acs/csi-provisioner:v1.4.0-aliyun
          args:
            - "--provisioner=nasplugin.csi.alibabacloud.com"
            - "--csi-address=\$(ADDRESS)"
            - "--volume-name-prefix=nas"
            - "--timeout=150s"
            - "--enable-leader-election=true"
            - "--leader-election-type=leases"
            - "--retry-interval-start=500ms"
            - "--v=5"
          env:
            - name: ADDRESS
              value: /var/lib/kubelet/csi-provisioner/nasplugin.csi.alibabacloud.com/csi.sock
          imagePullPolicy: "Always"
          volumeMounts:
            - name: nas-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/nasplugin.csi.alibabacloud.com
        - name: external-csi-snapshotter
          image: csi-image-prefix/acs/csi-snapshotter:v3.0.2-1038b92d8-aliyun
          args:
            - "--v=5"
            - "--csi-address=\$(ADDRESS)"
            - "--leader-election=true"
          env:
            - name: ADDRESS
              value: /csi/csi.sock
          imagePullPolicy: Always
          volumeMounts:
            - name: disk-provisioner-dir
              mountPath: /csi
        - name: external-snapshot-controller
          image: csi-image-prefix/acs/snapshot-controller:v3.0.2-1038b92d8-aliyun
          args:
            - "--v=5"
            - "--leader-election=true"
          imagePullPolicy: Always
        - name: csi-provisioner
          securityContext:
            privileged: true
            capabilities:
              add: ["SYS_ADMIN"]
            allowPrivilegeEscalation: true
          image: csi-image-prefix/acs/csi-plugin:csi-image-version
          imagePullPolicy: "Always"
          args:
            - "--endpoint=\$(CSI_ENDPOINT)"
            - "--v=2"
            - "--driver=nas,disk"
          env:
            - name: CSI_ENDPOINT
              value: unix://var/lib/kubelet/csi-provisioner/driverplugin.csi.alibabacloud.com-replace/csi.sock
            - name: MAX_VOLUMES_PERNODE
              value: "15"
            - name: SERVICE_TYPE
              value: "provisioner"
          livenessProbe:
            httpGet:
              path: /healthz
              port: healthz
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 5
          ports:
            - name: healthz
              containerPort: 11270
              protocol: TCP
          volumeMounts:
            - name: host-dev
              mountPath: /dev
              mountPropagation: "HostToContainer"
            - name: host-log
              mountPath: /var/log/
            - name: etc
              mountPath: /host/etc
            - name: disk-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/diskplugin.csi.alibabacloud.com
            - name: nas-provisioner-dir
              mountPath: /var/lib/kubelet/csi-provisioner/nasplugin.csi.alibabacloud.com
            - mountPath: /var/addon
              name: addon-token
              readOnly: true
          resources:
            limits:
              cpu: 1000m
              memory: 1000Mi
            requests:
              cpu: 100m
              memory: 100Mi
      volumes:
        - name: disk-provisioner-dir
          emptyDir: {}
        - name: nas-provisioner-dir
          emptyDir: {}
        - name: host-log
          hostPath:
            path: /var/log/
        - name: host-dev
          hostPath:
            path: /dev
        - name: addon-token
          secret:
            defaultMode: 420
            items:
            - key: addon.token.config
              path: token-config
            secretName: addon.csi.token
        - name: etc
          hostPath:
            path: /etc
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.3.0
    api-approved.kubernetes.io: "https://github.com/kubernetes-csi/external-snapshotter/pull/139"
  creationTimestamp: null
  name: volumesnapshotclasses.snapshot.storage.k8s.io
spec:
  group: snapshot.storage.k8s.io
  names:
    kind: VolumeSnapshotClass
    listKind: VolumeSnapshotClassList
    plural: volumesnapshotclasses
    singular: volumesnapshotclass
  scope: Cluster
  versions:
  - additionalPrinterColumns:
    - jsonPath: .driver
      name: Driver
      type: string
    - description: Determines whether a VolumeSnapshotContent created through the
        VolumeSnapshotClass should be deleted when its bound VolumeSnapshot is deleted.
      jsonPath: .deletionPolicy
      name: DeletionPolicy
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: Age
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: VolumeSnapshotClass specifies parameters that a underlying storage
          system uses when creating a volume snapshot. A specific VolumeSnapshotClass
          is used by specifying its name in a VolumeSnapshot object. VolumeSnapshotClasses
          are non-namespaced
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          deletionPolicy:
            description: deletionPolicy determines whether a VolumeSnapshotContent
              created through the VolumeSnapshotClass should be deleted when its bound
              VolumeSnapshot is deleted. Supported values are "Retain" and "Delete".
              "Retain" means that the VolumeSnapshotContent and its physical snapshot
              on underlying storage system are kept. "Delete" means that the VolumeSnapshotContent
              and its physical snapshot on underlying storage system are deleted.
              Required.
            enum:
            - Delete
            - Retain
            type: string
          driver:
            description: driver is the name of the storage driver that handles this
              VolumeSnapshotClass. Required.
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          parameters:
            additionalProperties:
              type: string
            description: parameters is a key-value map with storage driver specific
              parameters for creating snapshots. These values are opaque to Kubernetes.
            type: object
        required:
        - deletionPolicy
        - driver
        type: object
    served: true
    storage: true
    subresources: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.3.0
    api-approved.kubernetes.io: "https://github.com/kubernetes-csi/external-snapshotter/pull/139"
  creationTimestamp: null
  name: volumesnapshotcontents.snapshot.storage.k8s.io
spec:
  group: snapshot.storage.k8s.io
  names:
    kind: VolumeSnapshotContent
    listKind: VolumeSnapshotContentList
    plural: volumesnapshotcontents
    singular: volumesnapshotcontent
  scope: Cluster
  versions:
  - additionalPrinterColumns:
    - description: Indicates if a snapshot is ready to be used to restore a volume.
      jsonPath: .status.readyToUse
      name: ReadyToUse
      type: boolean
    - description: Represents the complete size of the snapshot in bytes
      jsonPath: .status.restoreSize
      name: RestoreSize
      type: integer
    - description: Determines whether this VolumeSnapshotContent and its physical
        snapshot on the underlying storage system should be deleted when its bound
        VolumeSnapshot is deleted.
      jsonPath: .spec.deletionPolicy
      name: DeletionPolicy
      type: string
    - description: Name of the CSI driver used to create the physical snapshot on
        the underlying storage system.
      jsonPath: .spec.driver
      name: Driver
      type: string
    - description: Name of the VolumeSnapshotClass to which this snapshot belongs.
      jsonPath: .spec.volumeSnapshotClassName
      name: VolumeSnapshotClass
      type: string
    - description: Name of the VolumeSnapshot object to which this VolumeSnapshotContent
        object is bound.
      jsonPath: .spec.volumeSnapshotRef.name
      name: VolumeSnapshot
      type: string
    - jsonPath: .metadata.creationTimestamp
      name: Age
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: VolumeSnapshotContent represents the actual "on-disk" snapshot
          object in the underlying storage system
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          spec:
            description: spec defines properties of a VolumeSnapshotContent created
              by the underlying storage system. Required.
            properties:
              deletionPolicy:
                description: deletionPolicy determines whether this VolumeSnapshotContent
                  and its physical snapshot on the underlying storage system should
                  be deleted when its bound VolumeSnapshot is deleted. Supported values
                  are "Retain" and "Delete". "Retain" means that the VolumeSnapshotContent
                  and its physical snapshot on underlying storage system are kept.
                  "Delete" means that the VolumeSnapshotContent and its physical snapshot
                  on underlying storage system are deleted. In dynamic snapshot creation
                  case, this field will be filled in with the "DeletionPolicy" field
                  defined in the VolumeSnapshotClass the VolumeSnapshot refers to.
                  For pre-existing snapshots, users MUST specify this field when creating
                  the VolumeSnapshotContent object. Required.
                enum:
                - Delete
                - Retain
                type: string
              driver:
                description: driver is the name of the CSI driver used to create the
                  physical snapshot on the underlying storage system. This MUST be
                  the same as the name returned by the CSI GetPluginName() call for
                  that driver. Required.
                type: string
              source:
                description: source specifies from where a snapshot will be created.
                  This field is immutable after creation. Required.
                properties:
                  snapshotHandle:
                    description: snapshotHandle specifies the CSI "snapshot_id" of
                      a pre-existing snapshot on the underlying storage system. This
                      field is immutable.
                    type: string
                  volumeHandle:
                    description: volumeHandle specifies the CSI "volume_id" of the
                      volume from which a snapshot should be dynamically taken from.
                      This field is immutable.
                    type: string
                type: object
              volumeSnapshotClassName:
                description: name of the VolumeSnapshotClass to which this snapshot
                  belongs.
                type: string
              volumeSnapshotRef:
                description: volumeSnapshotRef specifies the VolumeSnapshot object
                  to which this VolumeSnapshotContent object is bound. VolumeSnapshot.Spec.VolumeSnapshotContentName
                  field must reference to this VolumeSnapshotContent name for the
                  bidirectional binding to be valid. For a pre-existing VolumeSnapshotContent
                  object, name and namespace of the VolumeSnapshot object MUST be
                  provided for binding to happen. This field is immutable after creation.
                  Required.
                properties:
                  apiVersion:
                    description: API version of the referent.
                    type: string
                  fieldPath:
                    description: 'If referring to a piece of an object instead of
                      an entire object, this string should contain a valid JSON/Go
                      field access statement, such as desiredState.manifest.containers[2].
                      For example, if the object reference is to a container within
                      a pod, this would take on a value like: "spec.containers{name}"
                      (where "name" refers to the name of the container that triggered
                      the event) or if no container name is specified "spec.containers[2]"
                      (container with index 2 in this pod). This syntax is chosen
                      only to have some well-defined way of referencing a part of
                      an object. TODO: this design is not final and this field is
                      subject to change in the future.'
                    type: string
                  kind:
                    description: 'Kind of the referent. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                    type: string
                  name:
                    description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names'
                    type: string
                  namespace:
                    description: 'Namespace of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/'
                    type: string
                  resourceVersion:
                    description: 'Specific resourceVersion to which this reference
                      is made, if any. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency'
                    type: string
                  uid:
                    description: 'UID of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids'
                    type: string
                type: object
            required:
            - deletionPolicy
            - driver
            - source
            - volumeSnapshotRef
            type: object
          status:
            description: status represents the current information of a snapshot.
            properties:
              creationTime:
                description: creationTime is the timestamp when the point-in-time
                  snapshot is taken by the underlying storage system. In dynamic snapshot
                  creation case, this field will be filled in with the "creation_time"
                  value returned from CSI "CreateSnapshotRequest" gRPC call. For a
                  pre-existing snapshot, this field will be filled with the "creation_time"
                  value returned from the CSI "ListSnapshots" gRPC call if the driver
                  supports it. If not specified, it indicates the creation time is
                  unknown. The format of this field is a Unix nanoseconds time encoded
                  as an int64. On Unix, the command `date +%s%N` returns the current
                  time in nanoseconds since 1970-01-01 00:00:00 UTC.
                format: int64
                type: integer
              error:
                description: error is the latest observed error during snapshot creation,
                  if any.
                properties:
                  message:
                    description: 'message is a string detailing the encountered error
                      during snapshot creation if specified. NOTE: message may be
                      logged, and it should not contain sensitive information.'
                    type: string
                  time:
                    description: time is the timestamp when the error was encountered.
                    format: date-time
                    type: string
                type: object
              readyToUse:
                description: readyToUse indicates if a snapshot is ready to be used
                  to restore a volume. In dynamic snapshot creation case, this field
                  will be filled in with the "ready_to_use" value returned from CSI
                  "CreateSnapshotRequest" gRPC call. For a pre-existing snapshot,
                  this field will be filled with the "ready_to_use" value returned
                  from the CSI "ListSnapshots" gRPC call if the driver supports it,
                  otherwise, this field will be set to "True". If not specified, it
                  means the readiness of a snapshot is unknown.
                type: boolean
              restoreSize:
                description: restoreSize represents the complete size of the snapshot
                  in bytes. In dynamic snapshot creation case, this field will be
                  filled in with the "size_bytes" value returned from CSI "CreateSnapshotRequest"
                  gRPC call. For a pre-existing snapshot, this field will be filled
                  with the "size_bytes" value returned from the CSI "ListSnapshots"
                  gRPC call if the driver supports it. When restoring a volume from
                  this snapshot, the size of the volume MUST NOT be smaller than the
                  restoreSize if it is specified, otherwise the restoration will fail.
                  If not specified, it indicates that the size is unknown.
                format: int64
                minimum: 0
                type: integer
              snapshotHandle:
                description: snapshotHandle is the CSI "snapshot_id" of a snapshot
                  on the underlying storage system. If not specified, it indicates
                  that dynamic snapshot creation has either failed or it is still
                  in progress.
                type: string
            type: object
        required:
        - spec
        type: object
    served: true
    storage: true
    subresources:
      status: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  annotations:
    controller-gen.kubebuilder.io/version: v0.3.0
    api-approved.kubernetes.io: "https://github.com/kubernetes-csi/external-snapshotter/pull/139"
  creationTimestamp: null
  name: volumesnapshots.snapshot.storage.k8s.io
spec:
  group: snapshot.storage.k8s.io
  names:
    kind: VolumeSnapshot
    listKind: VolumeSnapshotList
    plural: volumesnapshots
    singular: volumesnapshot
  scope: Namespaced
  versions:
  - additionalPrinterColumns:
    - description: Indicates if a snapshot is ready to be used to restore a volume.
      jsonPath: .status.readyToUse
      name: ReadyToUse
      type: boolean
    - description: Name of the source PVC from where a dynamically taken snapshot
        will be created.
      jsonPath: .spec.source.persistentVolumeClaimName
      name: SourcePVC
      type: string
    - description: Name of the VolumeSnapshotContent which represents a pre-provisioned
        snapshot.
      jsonPath: .spec.source.volumeSnapshotContentName
      name: SourceSnapshotContent
      type: string
    - description: Represents the complete size of the snapshot.
      jsonPath: .status.restoreSize
      name: RestoreSize
      type: string
    - description: The name of the VolumeSnapshotClass requested by the VolumeSnapshot.
      jsonPath: .spec.volumeSnapshotClassName
      name: SnapshotClass
      type: string
    - description: The name of the VolumeSnapshotContent to which this VolumeSnapshot
        is bound.
      jsonPath: .status.boundVolumeSnapshotContentName
      name: SnapshotContent
      type: string
    - description: Timestamp when the point-in-time snapshot is taken by the underlying
        storage system.
      jsonPath: .status.creationTime
      name: CreationTime
      type: date
    - jsonPath: .metadata.creationTimestamp
      name: Age
      type: date
    name: v1beta1
    schema:
      openAPIV3Schema:
        description: VolumeSnapshot is a user request for either creating a point-in-time
          snapshot of a persistent volume, or binding to a pre-existing snapshot.
        properties:
          apiVersion:
            description: 'APIVersion defines the versioned schema of this representation
              of an object. Servers should convert recognized schemas to the latest
              internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
            type: string
          kind:
            description: 'Kind is a string value representing the REST resource this
              object represents. Servers may infer this from the endpoint the client
              submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
            type: string
          spec:
            description: 'spec defines the desired characteristics of a snapshot requested
              by a user. More info: https://kubernetes.io/docs/concepts/storage/volume-snapshots#volumesnapshots
              Required.'
            properties:
              source:
                description: source specifies where a snapshot will be created from.
                  This field is immutable after creation. Required.
                properties:
                  persistentVolumeClaimName:
                    description: persistentVolumeClaimName specifies the name of the
                      PersistentVolumeClaim object in the same namespace as the VolumeSnapshot
                      object where the snapshot should be dynamically taken from.
                      This field is immutable.
                    type: string
                  volumeSnapshotContentName:
                    description: volumeSnapshotContentName specifies the name of a
                      pre-existing VolumeSnapshotContent object. This field is immutable.
                    type: string
                type: object
              volumeSnapshotClassName:
                description: 'volumeSnapshotClassName is the name of the VolumeSnapshotClass
                  requested by the VolumeSnapshot. If not specified, the default snapshot
                  class will be used if one exists. If not specified, and there is
                  no default snapshot class, dynamic snapshot creation will fail.
                  Empty string is not allowed for this field. TODO(xiangqian): a webhook
                  validation on empty string. More info: https://kubernetes.io/docs/concepts/storage/volume-snapshot-classes'
                type: string
            required:
            - source
            type: object
          status:
            description: 'status represents the current information of a snapshot.
              NOTE: status can be modified by sources other than system controllers,
              and must not be depended upon for accuracy. Controllers should only
              use information from the VolumeSnapshotContent object after verifying
              that the binding is accurate and complete.'
            properties:
              boundVolumeSnapshotContentName:
                description: 'boundVolumeSnapshotContentName represents the name of
                  the VolumeSnapshotContent object to which the VolumeSnapshot object
                  is bound. If not specified, it indicates that the VolumeSnapshot
                  object has not been successfully bound to a VolumeSnapshotContent
                  object yet. NOTE: Specified boundVolumeSnapshotContentName alone
                  does not mean binding       is valid. Controllers MUST always verify
                  bidirectional binding between       VolumeSnapshot and VolumeSnapshotContent
                  to avoid possible security issues.'
                type: string
              creationTime:
                description: creationTime is the timestamp when the point-in-time
                  snapshot is taken by the underlying storage system. In dynamic snapshot
                  creation case, this field will be filled in with the "creation_time"
                  value returned from CSI "CreateSnapshotRequest" gRPC call. For a
                  pre-existing snapshot, this field will be filled with the "creation_time"
                  value returned from the CSI "ListSnapshots" gRPC call if the driver
                  supports it. If not specified, it indicates that the creation time
                  of the snapshot is unknown.
                format: date-time
                type: string
              error:
                description: error is the last observed error during snapshot creation,
                  if any. This field could be helpful to upper level controllers(i.e.,
                  application controller) to decide whether they should continue on
                  waiting for the snapshot to be created based on the type of error
                  reported.
                properties:
                  message:
                    description: 'message is a string detailing the encountered error
                      during snapshot creation if specified. NOTE: message may be
                      logged, and it should not contain sensitive information.'
                    type: string
                  time:
                    description: time is the timestamp when the error was encountered.
                    format: date-time
                    type: string
                type: object
              readyToUse:
                description: readyToUse indicates if a snapshot is ready to be used
                  to restore a volume. In dynamic snapshot creation case, this field
                  will be filled in with the "ready_to_use" value returned from CSI
                  "CreateSnapshotRequest" gRPC call. For a pre-existing snapshot,
                  this field will be filled with the "ready_to_use" value returned
                  from the CSI "ListSnapshots" gRPC call if the driver supports it,
                  otherwise, this field will be set to "True". If not specified, it
                  means the readiness of a snapshot is unknown.
                type: boolean
              restoreSize:
                type: string
                description: restoreSize represents the complete size of the snapshot
                  in bytes. In dynamic snapshot creation case, this field will be
                  filled in with the "size_bytes" value returned from CSI "CreateSnapshotRequest"
                  gRPC call. For a pre-existing snapshot, this field will be filled
                  with the "size_bytes" value returned from the CSI "ListSnapshots"
                  gRPC call if the driver supports it. When restoring a volume from
                  this snapshot, the size of the volume MUST NOT be smaller than the
                  restoreSize if it is specified, otherwise the restoration will fail.
                  If not specified, it indicates that the size is unknown.
                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                x-kubernetes-int-or-string: true
            type: object
        required:
        - spec
        type: object
    served: true
    storage: true
    subresources:
      status: {}
status:
  acceptedNames:
    kind: ""
    plural: ""
  conditions: []
  storedVersions: []
EOF

# get registry address
imageBefore=`kubectl describe ds csi-plugin -nkube-system | grep Image: | awk 'NR==2 {print $2}'`
imagePrefix=`kubectl describe ds csi-plugin -nkube-system | grep Image: | awk 'NR==2 {print $2}' | awk -F: '{print $1}' | awk -F/ '{print $1}'`

# New image name
imageName=${imagePrefix}/acs/csi-plugin:$imageVersion

## Check current version
if [[ $imagePrefix != registry* ]] || [[ $imagePrefix != *aliyuncs.com ]]; then
    echo "Setting image is not expect: "$imagePrefix
    exit 0
fi

if [[ $imageVersion != *aliyun ]]; then
    echo "current image version is not expect: "$imageVersion
    exit 0
fi

## Delete old plugin
kubectl delete deployment csi-provisioner -nkube-system

if [ "$masterCount" -eq "0" ]; then
  cat .aliyun-csi-provisioner-managed.yaml | sed "s/csi-image-prefix/$imagePrefix/" | sed "s/csi-image-version/$imageVersion/" | sed "s/volume-define-string/$volumeDefineStr/" | sed "s/volume-mount-string/$volumeMountStr/" | kubectl apply -f -
else
  cat .aliyun-csi-provisioner-dedicate.yaml | sed "s/csi-image-prefix/$imagePrefix/" | sed "s/csi-image-version/$imageVersion/" | sed "s/volume-define-string/$volumeDefineStr/" | sed "s/volume-mount-string/$volumeMountStr/" | kubectl apply -f -
fi

echo "Upgrade csi provisioner from $imageBefore to $imageName"