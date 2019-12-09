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

# Retrieve configuration from environment

hlspath = ref getenv("HLSPATH")

if !hlspath == "" then
  hlspath := "/hls"
end

### Define Prometheus metrics

latency_metric = prometheus.latency(labels=["radio","type","name"])
is_ready_metric = prometheus.gauge(labels=["radio","type","name"],help="is source ready?","liquidsoap_is_ready")
is_playing_metric = prometheus.gauge(labels=["radio","type","name"],help="is source playing?","liquidsoap_is_playing")
duration_unready_seconds_metric = prometheus.counter(labels=["radio","type","name"],help="Cumulative duration in seconds of the source in unreadystate","liquidsoap_duration_unready_seconds")
is_blank_metric = prometheus.gauge(labels=["radio","type","name"],help="is source blank?","liquidsoap_is_blank")

# Prometheus metrics helpers
def check_if_ready(set_is_ready, increase_duration_unready_seconds, source) =
  def callback() =
    if source.is_ready(source) then
      set_is_ready(1.)
    else
      set_is_ready(0.)
      increase_duration_unready_seconds(0.1)
    end
    0.1
  end
  callback
end

def source_tag(s,tag) =
  def f(_)
    [("source_tag",tag)]
  end
  map_metadata(insert_missing=true,f,s)
end

### END Define Prometheus metrics

### Inputs

srt1 = input.srt(id="input_srt1", 
                 port=10000)

# Get metrics
latency_metric(label_values=["default","input","srt1"],srt1)
set_is_ready = is_ready_metric(label_values=["default","input","srt1"])
increase_duration_unready_seconds = duration_unready_seconds_metric(label_values=["default","input","srt1"])
thread.run.recurrent(delay=0.,check_if_ready(set_is_ready, increase_duration_unready_seconds, srt1))
set_is_playing_srt1 = is_playing_metric(label_values=["default","input","srt1"])

# Wrap input in a buffer
srt1 = buffer(id="buffer_srt1",
              fallible=true, 
              max=3.0,
              srt1)

# Tag source with it's name in metadata
srt1 = source_tag(srt1, "srt1")

srt2 = input.srt(id="input_srt2", 
                     port=10001)

# Get metrics
latency_metric(label_values=["default","input","srt2"],srt2)
set_is_ready = is_ready_metric(label_values=["default","input","srt2"])
increase_duration_unready_seconds = duration_unready_seconds_metric(label_values=["default","input","srt2"])
thread.run.recurrent(delay=0.,check_if_ready(set_is_ready, increase_duration_unready_seconds, srt2))
set_is_playing_srt2 = is_playing_metric(label_values=["default","input","srt2"])

# Wrap input in a buffer
srt2 = buffer(id="buffer_srt2",
              fallible=true, 
              max=3.0,
              srt2)

# Tag source with it's name in metadata
srt2 = source_tag(srt2, "srt2")

# define safe blank source
safe_blank = blank(id="safe_blank")
safe_blank = source_tag(safe_blank, "safe_blank")
set_is_playing_safe_blank = is_playing_metric(label_values=["default","input","safe_blank"])

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

# Get metrics on output
latency_metric(label_values=["default","output","radio_prod"],radio_prod)
set_is_ready = is_ready_metric(label_values=["default","output","radio_prod"])
increase_duration_unready_seconds = duration_unready_seconds_metric(label_values=["default","output","radio_prod"])
thread.run.recurrent(delay=0.,check_if_ready(set_is_ready, increase_duration_unready_seconds, radio_prod))

def check_is_playing(metadata) =
  source_tag = list.assoc(default="", "source_tag", metadata)

  if source_tag == "srt1" then
    set_is_playing_srt1(1.)
  else
    set_is_playing_srt1(0.)
  end
  if source_tag == "srt2" then
    set_is_playing_srt2(1.)
  else
    set_is_playing_srt2(0.)
  end
  if source_tag == "safe_blank" then
    set_is_playing_safe_blank(1.)
  else
    set_is_playing_safe_blank(0.)
  end
end

# Check output metadata to set is_playing metric
radio_prod = on_metadata(check_is_playing, radio_prod)

# Detect blank before output

set_is_blank = is_blank_metric(label_values=["default","output","radio_prod"])

def noise_detect_handler() =
  set_is_blank(0.0)
end

def blank_detect_handler() =
  set_is_blank(1.0)
end

radio_prod = on_blank(id="on_blank_radio_prod",
                      max_blank=1.0,
                      min_noise=0.0,
                      on_noise=noise_detect_handler,
                      start_blank=false,
                      threshold=-40.0,
                      track_sensitive=true,
                      blank_detect_handler,
                      radio_prod)


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

streams_info = [("aac_lofi",(78000,"mp4a.40.2","ts")),
                ("aac_midfi",(160000,"mp4a.40.2","ts")),
                ("aac_hifi",(252000,"mp4a.40.2","ts"))]

# Output to HLS

def segment_name(~position,~extname,stream_name) =
  timestamp = int_of_float(gettimeofday())
  duration = 2
  "#{stream_name}_#{duration}_#{timestamp}_#{position}.ts"
end

def on_file_change(~state,fname) =
  if state == "closed" and file.extension(fname) != '.m3u8' then
    log.important(label="hls", "Segment #{fname} created")
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
                persist=true,
                persist_at="state.config",
                !hlspath,
                [("aac_lofi",aac_lofi), 
                 ("aac_midfi", aac_midfi), 
                 ("aac_hifi", aac_hifi)],
                radio_prod)

### END Outputs