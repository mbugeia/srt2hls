#!/usr/bin/liquidsoap

# General settings

set("log.level",3)
set("log.stdout", true)

# Telnet server settings

set("server.telnet.bind_addr", "0.0.0.0")
set("server.telnet.port", 8500)
set("server.telnet", true)

# Audio settings

set("frame.audio.samplerate",44100)
set("frame.audio.channels",2)
set("audio.converter.samplerate.libsamplerate.quality","fast")

# Retrieve configuration from environment

hlspath = ref getenv("HLSPATH")

if !hlspath == "" then
  hlspath := "/hls"
end

# Define inputs

srt1 = buffer(id="buffer_srt1",
              fallible=true, 
              max=3.0,
              input.srt(id="input_srt1", 
                        port=10000))
srt2 = buffer(id="buffer_srt2",
              fallible=true, 
              max=3.0,
              input.srt(id="input_srt2", 
                        port=10001, 
                        clock_safe=false))

input_list = ["srt1", "srt2"]

# Radio logic

live_source = ref "srt1"

def setlivesource(s) =
  if not list.mem(s,input_list) then
    "error - Source does not exist! Doing nothing."
  else
    live_source := s
    "Live source set to #{s}"
  end
end

def getlivesource(_) =
  !live_source
end

def is_playing(n) =
  fun () -> n == !live_source
end

server.register(description="Get live source",
                usage= "getlivesource",
                "getlivesource",
                getlivesource)

server.register(description="Set live source",
                usage= "setlivesource <livesource>",
                "setlivesource",
                setlivesource)

live = switch(id="switch_live", 
              track_sensitive=false, 
              [(is_playing("srt1"), srt1), 
              (is_playing("srt2"), srt2)])

radio_prod = mksafe(fallback(id="fallback_prod",
                             track_sensitive=false,
                             [live, srt1, srt2]))

# Define output formats

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

