# srt2hls

Simple audio HLS streaming server.

## Intro

The goal of this program is to receive an audio stream with [SRT](https://github.com/Haivision/srt) and broadcast it with HLS. It can serve as a CDN origin server or as a set-and-forget streaming server.

## How it works

srt2hls use [Liquidsoap](https://www.liquidsoap.info) to receive a stream and encode it in HLS, then it use [nginx] (https://www.nginx.com/) to serve HLS content.

The Liquidsoap container, by default, run radio/live.liq script. It's a fully functionnal example that will :
1. Receive an SRT input on port 10000
2. Encode it in aac with 3 quality
3. Segment it in HLS format in /hls directory

The Nginx container come with a specific configuration to serve HLS content with proper Content-Type, CORS and Cache-Control headers. It need read only access to /hls directory to serve HLS segments and playlists.

## Setup
### With docker compose
```bash
mkdir hls
sudo chown -R 2001:2000 hls
sudo docker-compose up
```

### Local installation requirements

[Liquidsoap](https://www.liquidsoap.info) 1.5.0+ (not released yet, use master)

ffmpeg compiled with fdkaac support (the one on liquidsoap debian/ubuntu repository is fine)


## Basic usage

### Listening
By default the encoder send blank HLS segments, that mean if it's started, you can already listen the blank stream.

```bash
ffplay http://localhost:8080/live.m3u8
vlc http://localhost:8080/live.m3u8
```

### Switch live source

The default script allow to switch the output between inputs.

```bash
# Check available input to switch to
curl http://localhost:8080/api/list?livesource
# Switch the livesource
curl http://localhost:8080/api/set?livesource=srt2
curl http://localhost:8080/api/set?livesource=srt1
# check the current live source
curl http://localhost:8080/api/get?livesource
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

### Monitoring

#### Grafana
http://localhost:3000/

![Alt text](img/monitoring.png?raw=true "Liquidsoap Dashboard in Grafana")
#### Prometheus
http://localhost:9090/

## Development

### Build images
```bash
sudo docker-compose build
```

## Thanks

Folks of [Liquidsoap](https://www.liquidsoap.info)

Monitoring stack is mostly inspired by https://github.com/stefanprodan/dockprom
