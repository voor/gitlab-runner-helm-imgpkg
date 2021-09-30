# Creating a imgpkg bundle with helm (and still using ytt and kbld)

This repository is a sample of how an organization took a Helm chart (Gitlab Runner Helm chart) and enhanced it using Carvel to provide some additional value:

* Reliable image relocation (so when the chart was moved the containers came with it)
* Immutable image references (sha256 instead of tags)
* Additional ways to configure the Gitlab Runner config (which is currently very limited in the helm chart)
* More reliable way to add in tags
* Namespace creation and moving to different namespaces without needing the helm cli
* "Gitops ready" for use in kapp-controller

Directory layout:
```
.
├── build.sh
├── bundle
│   ├── chart
│   │   ├── ...
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── values.yaml.original
│   └── config
│       └── 00-additional.yaml
├── helm
│   └── values-overlay.yaml
├── manifests
│   └── 00-additional.yaml
├── README.md
├── vendir.yml
└── ...
```

`vendir` downloads the chart and places it into the `/bundle/chart` location.  This provides a new location that doesn't conflict with standard practices for using the `config` folder for pure Kubernetes manifests.  Additional manifests can be included in `config`, these can later be referenced in the `ytt` phase to not interfer with the files coming from stdin for the helm templating phase.

Since helm doesn't complain, nor does ytt complain, when there are additional values provided into helm or ytt, you can actually use the same values file for both steps in the process.  This allows it to be easier as an end user to know when values should be included.  The file in `helm/values-overlay.yaml` is actually a ytt overlay that will change existing values in the helm chart, or add your own on top.

Generate a sample:

```
./build.sh gitlab-runner sample
```

Push the bundle up to an image repository for use in a Package CR:

```
./build.sh gitlab-runner deploy gcr.io/pa-rvanvoorhees/charts/gitlab-runner
```

There is a sample of the completed product hosted here:
```
gcr.io/pa-rvanvoorhees/charts/gitlab-runner/imgpkg/charts/gitlab-runner@sha256:0a901be2cd24289a7722a94d5e0fc26452026e9bc7738d25ed41f5ea4f09e782
```

And you would want to create a Package CR that contained the following:

```
  fetch:
  - imgpkgBundle:
      image: gcr.io/pa-rvanvoorhees/charts/gitlab-runner/imgpkg/charts/gitlab-runner@sha256:0a901be2cd24289a7722a94d5e0fc26452026e9bc7738d25ed41f5ea4f09e782
  template:
  - helmTemplate:
      name: #@ "runner-{}".format(runner.name)
      namespace: #@ "{}".format(runner.namespace)
      path: chart/
  - ytt:
      ignoreUnknownComments: true
      paths:
      - '-'
      #! This was a really great idea to just use the same values file from helm and ytt.
      - chart/values.yaml
      - config/
  - kbld:
      paths:
      - '-'
      - .imgpkg/images.yml
  deploy:
  - kapp:
      rawOptions:
      - --wait-timeout=5m
      - --diff-changes=true
```