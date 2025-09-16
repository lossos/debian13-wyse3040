# debian13-wyse3040
Preseed and Build Iso for Debian Trixie on Wyse 3040

## Build ISO with Docker 

```bash
docker build -t preseed-iso .
docker run --rm -v $(pwd):/out preseed-iso
```
