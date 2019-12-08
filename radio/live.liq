#!/usr/bin/liquidsoap

# General settings

set("log.level",3)
set("log.stdout", true)

# Telnet server settings

set("server.telnet.bind_addr", "0.0.0.0")
set("server.telnet.port", 8500)
set("server.telnet", true)

# Harbor HTTP server settings
set("harbor.bind_addrs",["0.0.0.0"])
set("harbor.max_connections",10)
set("harbor.timeout",10.)
set("harbor.verbose",false)

# Prometheus settings
set("prometheus.server",true)
set("prometheus.server.port",9090)

# Audio settings

set("frame.audio.samplerate",44100)
set("frame.audio.channels",2)
set("audio.converter.samplerate.libsamplerate.quality","fast")

# Clocks settings
set("root.max_latency",5.)
set("clock.allow_streaming_errors",false)

# Internal scheduler settings
set("scheduler.fast_queues",1)
set("scheduler.generic_queues",4)

# Retrieve configuration from environment

hlspath = ref getenv("HLSPATH")

if !hlspath == "" then
  hlspath := "/hls"
end

### Prometheus metrics

latency_metric = prometheus.latency(labels=["source"])

is_ready_metric = prometheus.gauge(labels=["source"],help="is source ready?","liquidsoap_is_ready")

### END Prometheus metrics

### Inputs

srt1 = buffer(id="buffer_srt1",
              fallible=true, 
              max=3.0,
              input.srt(id="input_srt1", 
                        port=10000))

latency_metric(label_values=["srt1"],srt1)

set_is_ready = is_ready_metric(label_values=["srt1"])
def check_if_ready() =
  if source.is_ready(srt1) then
    set_is_ready(1.)
  else
    set_is_ready(0.)
  end
  0.1
end
thread.run.recurrent(delay=0.,check_if_ready)


srt2 = buffer(id="buffer_srt2",
              fallible=true, 
              max=3.0,
              input.srt(id="input_srt2", 
                        port=10001, 
                        clock_safe=false))

latency_metric(label_values=["srt2"],srt2)

set_is_ready = is_ready_metric(label_values=["srt2"])
def check_if_ready() =
  if source.is_ready(srt2) then
    set_is_ready(1.)
  else
    set_is_ready(0.)
  end
  0.1
end
thread.run.recurrent(delay=0.,check_if_ready)

safe_blank = blank(id="safe_blank")

live_input_list = ["srt1", "srt2"]

### END Inputs

### Radio logic

live_source = ref "srt1"

def is_playing(n) =
  fun () -> n == !live_source
end

live = switch(id="switch_live", 
              track_sensitive=false, 
              [(is_playing("srt1"), srt1), 
              (is_playing("srt2"), srt2)])

radio_prod = fallback(id="fallback_prod",
                             track_sensitive=false,
                             [live, srt1, srt2, safe_blank])

latency_metric(label_values=["radio_prod"],radio_prod)

### END Radio logic

### HTTP API

# Define default http response
def http_response(level="error",msg="Unknow error",code=500) =
    log.important(label="httplog", "#{level} #{msg} #{code}")
    http_response(code=code,
                  headers=[("Content-Type","application/json")],
                  data='{"level": #{json_of(level)}, "msg": #{json_of(msg)},"code": #{json_of(code)}}')
end

# Handle /get arguments
def getarghandler(arg) =
  let (key, _) = arg
  if key == "livesource" then
    value = !live_source
    ("info", "Live source is set to #{value}", 200)
  else
    ("error", "Unrecognized argument #{key}", 400)
  end
end

# Handle /set arguments
def setarghandler(arg) =
  let (key, value) = arg
  if key == "livesource" then
    if not list.mem(value,live_input_list) then
      ("error", "Source #{value} does not exist", 400)
    else
      live_source := value
      ("info", "Live source set to #{value}", 200)
    end
  else
    ("error", "Unrecognized argument #{key}", 400)
  end
end

# Handle /list arguments
def listarghandler(arg) =
  let (key, _) = arg
  if key == "livesource" then
    list = string.concat(separator=", ",live_input_list)
    ("info", "Available live source are: #{list}", 200)
  else
    ("error", "Unrecognized argument #{key}", 400)
  end
end

# Define routes
def routehandler(req, args) =
  if req == "/set" then
    if list.length(args) == 1 then
      setarghandler(list.hd(default=("none",""), args))
    else
      ("error","Route #{req} only support 1 argument",400)
    end
  elsif req == "/get" then
    getarghandler(list.hd(default=("none",""), args))
  elsif req == "/list" then
    listarghandler(list.hd(default=("none",""), args))
  else
    ("error","Route #{req} does not exist",404)
  end
end

# Default httphandler
def httphandler(~protocol,~data,~headers,uri) =
  let (req, args) = url.split(uri)
  let (level, msg, code) = routehandler(req, args)
  http_response(level, msg, code)
end

harbor.http.register(port=8081,method="GET","^/",httphandler)

### END HTTP API

### Telnet API
def setlivesource(s) =
  if not list.mem(s,live_input_list) then
    "error - Source does not exist! Doing nothing."
  else
    live_source := s
    "Live source set to #{s}"
  end
end

def getlivesource(_) =
  !live_source
end

server.register(description="Get live source",
                usage= "getlivesource",
                "getlivesource",
                getlivesource)

server.register(description="Set live source",
                usage= "setlivesource <livesource>",
                "setlivesource",
                setlivesource)

### END Telnet API

### Outputs

# Define outputs formats

aac_lofi = %ffmpeg(format="mpegts",
                   codec="libfdk_aac",
                   channels=2,
                   ar=44100,
                   b="32k",
                   afterburner=1,
                   profile="aac_low")

aac_midfi = %ffmpeg(format="mpegts",
                   codec="libfdk_aac",
                   channels=2,
                   ar=44100,
                   b="96k",
                   afterburner=1,
                   profile="aac_low")

aac_hifi = %ffmpeg(format="mpegts",
                   codec="libfdk_aac",
                   channels=2,
                   ar=44100,
                   b="192k",
                   afterburner=1,
                   profile="aac_low")

# Defines stream infos that cannot be guessed by liqudisoap

streams_info = [("aac-lofi",(78000,"mp4a.40.2","ts")),
                ("aac-midfi",(160000,"mp4a.40.2","ts")),
                ("aac-hifi",(252000,"mp4a.40.2","ts"))]

# Output to HLS

def segment_name(~position,~extname,stream_name) =
  timestamp = int_of_float(gettimeofday())
  duration = 2
  "#{stream_name}-#{duration}-#{timestamp}-#{position}.ts"
end

def on_file_change(~state,fname) =
  def make_configmap(type) =
    def create_configmap() =
        system("kubectl create configmap liquidsoap-0-#{path.basename(fname)} --from-file=#{fname} --dry-run=true -o yaml | kubectl label -f- --dry-run -o yaml --local type=#{type} | kubectl apply -f -")
      (-1.)
    end
    create_configmap
  end
  def make_delete_configmap() =
    def delete_configmap() =
        system("kubectl delete configmap liquidsoap-0-#{path.basename(fname)}")
      (-1.)
    end
    delete_configmap
  end
  if state == "closed" then
    if file.extension(fname) != '.m3u8' then
      log.important(label="hls", "Segment #{fname} created")
      thread.run.recurrent(delay=0.,fast=false,make_configmap("segment"))
    else 
      thread.run.recurrent(delay=0.,fast=false,make_configmap("playlist"))
    end
  elsif state == "deleted" then
    thread.run.recurrent(delay=0.,fast=false,make_delete_configmap())
  end
end

output.file.hls(id="output_hls",
                playlist="live.m3u8",
                segment_duration=2.0,
                segments=3,
                segments_overhead=10,
                segment_name=segment_name,
                streams_info=streams_info,
                on_file_change=on_file_change,
                !hlspath,
                [("aac-lofi",aac_lofi), 
                 ("aac-midfi", aac_midfi), 
                 ("aac-hifi", aac_hifi)],
                radio_prod)

### END Outputs