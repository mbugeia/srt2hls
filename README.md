# srt2hls

Simple audio HLS streaming server.

## Intro

The goal of this program is to receive an audio stream with [SRT](https://github.com/Haivision/srt) and broadcast it with HLS. It can serve as a CDN origin server or as a set-and-forget streaming server.

## Architecture

live.liq
Liquidsoap will listen an SRT stream on port 10000 and encode it

Nginx serve segments and playlist.

## Setup
### With docker compose
```bash
mkdir hls
chown -R 2001:2000 hls
sudo docker-compose up
```

### With docker
```bash
sudo docker run -it --rm -v $(pwd)/hls:/hls -p 8080:80 privyplace/nginx
sudo docker run -it --rm -v $(pwd)/hls:/hls -v $(pwd)/radio:/radio -p 10000:10000/udp privyplace/liquidsoap:master
```

### Local installation requirements

https://www.liquidsoap.info/ 1.4.0+ (not released yet, use master)

ffmpeg compiled with fdkaac support (the one on liquidsoap debian/ubuntu repository is fine)


## Basic usage

### Listening
By default the encoder send blank HLS segments, that mean if it's started, you can already listen the blank stream.

```bash
ffplay http://127.0.0.1:8080
vlc http://127.0.0.1:8080
```

### Sending audio to the streaming server

#### Using ffmpeg
Requirement : ffmpeg compiled with srt support (the one on liquidsoap debian/ubuntu repository is fine)

```bash
# static file
ffmpeg -re -i $AUDIOFILE -vn -f wav -codec:a pcm_s16le srt://127.0.0.1:10000
# live stream
ffmpeg -i $LIVESTREAM -vn -f wav -codec:a pcm_s16le srt://127.0.0.1:10000
```

## Development

### Build images
```bash
sudo docker-compose build
sudo docker build -t privyplace/nginx:latest ./nginx
sudo docker build -t privyplace/liquidsoap:master ./liquidsoap
```
## TODO

- [ ] Secure input : for now it can be hijacked by everyone who have access to the port 10000 of liquidsoap so only trusted network should be allowed as input.
- [ ] Script customization (templating and/or conf file/environment variables 
- [ ] Multiple input with priority logic
- [ ] External CDN export (s3, gcs,...)
- [ ] ...