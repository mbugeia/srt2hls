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

# Define inputs


srt1 = input.srt(port=10000)
srt2 = input.srt(port=10001, clock_safe=false)

# Radio logic

play_srt1 = ref true
play_srt2 = ref false

def getlivesource(dummy) =
  if !play_srt1 == true then
    "Live source is srt1"
  elsif !play_srt2 == true then
    "Live source is srt2"
  else
    "Unknown live source, that s unexpected."
  end
end

def setlivesource(source) =
  if source == "srt1" then
    play_srt1 := true
    play_srt2 := false
    "Live source set to srt1"
  elsif source == "srt2" then
    play_srt1 := false
    play_srt2 := true
    "Live source set to srt2"
  else
    "Unknown source, doing nothing."
  end
end

server.register(description="Get live source", 
                usage= "getlivesource",
                "getlivesource", 
                getlivesource)

server.register(description="Set live source", 
                usage= "setlivesource <livesource>",
                "setlivesource", 
                setlivesource)

radio_prod = mksafe(switch(track_sensitive=false, [
                          ({!play_srt1},srt1), 
                          ({!play_srt2},srt2)
                          ]))

# Define output formats

aac_lofi = %ffmpeg(format="mpegts",
                   codec="libfdk_aac",
                   channels=2,
                   ar=44100,
                   b="16k",
                   afterburner=1,
                   profile="aac_he_v2")

aac_midfi = %ffmpeg(format="mpegts",
                   codec="libfdk_aac",
                   channels=2,
                   ar=44100,
                   b="48k",
                   afterburner=1,
                   profile="aac_low")

aac_hifi = %ffmpeg(format="mpegts",
                   codec="libfdk_aac",
                   channels=2,
                   ar=44100,
                   b="96k",
                   afterburner=1,
                   profile="aac_low")

streams_info = [("aac_lofi",(40000,"mp4a.40.29","ts")),
                ("aac_midfi",(110000,"mp4a.40.2","ts")),
                ("aac_hifi",(220000,"mp4a.40.2","ts"))]

# Output to HLS

def segment_name(~position,~extname,stream_name) =
  timestamp = int_of_float(gettimeofday())
  duration = 2
  "#{stream_name}_#{duration}_#{timestamp}_#{position}.ts"
end

# def on_file_change(~state,fname) =
#   if state == "closed" then
#     print("Uploading #{fname} to s3://test.hls/#{path.basename(fname)}")
#     def f() =
#       system("aws s3 cp --acl public-read #{fname} s3://test.hls/#{path.basename(fname)}")
#       (-1.)
#     end
#     add_timeout(fast=false,0.,f)
#   elsif state == "deleted" then
#     fname = path.basename(fname)
#     print("Deleting s3://test.hls/#{fname}")
#     def f() =
#       system("aws s3 rm s3://test.hls/#{fname}")
#       (-1.)
#     end
#     add_timeout(fast=false,0.,f)
#   end
# end

output.file.hls(playlist="live.m3u8",
                segment_duration=2.0,
                segments=5,
                segments_overhead=5,
                segment_name=segment_name,
                streams_info=streams_info,
                persist=true,
                persist_at="state.config",
                "/hls",
                [("aac_lofi",aac_lofi), 
                 ("aac_midfi", aac_midfi), 
                 ("aac_hifi", aac_hifi)],
                radio_prod)

