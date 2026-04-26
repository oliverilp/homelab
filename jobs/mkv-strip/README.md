# mkv-strip

Small maintenance job for remuxing MKV files and removing unwanted Russian and Ukrainian audio/subtitle tracks without re-encoding.

The container uses the official Debian-based Python slim image plus `ffmpeg`. The Python script only uses the standard library, so there is no virtualenv or dependency lockfile.

Runtime configuration lives in the Kubernetes ConfigMap at `k8s/mkv-strip/mkv-strip-configmap.yaml`. The CronJob and manual Job both read the same config file.

Manual local run:

```bash
python3 jobs/mkv-strip/mkv_strip.py --recursive --keep-going --in-place /path/to/media
```

Manual Kubernetes run:

```bash
kubectl create -f k8s/mkv-strip/mkv-strip-job.yaml
```
