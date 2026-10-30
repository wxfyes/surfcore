import asyncio
import sys
import argparse
from edge_tts import Communicate

async def main():
    parser = argparse.ArgumentParser(description="Edge TTS 独立便携生成器")
    parser.add_argument("--voice", default="zh-CN-XiaoxiaoNeural", help="Voice model")
    parser.add_argument("--rate", default="-12%", help="Rate adjustment (e.g. -12%)")
    parser.add_argument("--pitch", default="+2Hz", help="Pitch adjustment (e.g. +2Hz)")
    parser.add_argument("--text", help="Text to synthesize")
    parser.add_argument("--file", help="Path to UTF-8 text file containing text to synthesize")
    parser.add_argument("--write-media", required=True, help="Output media file path")
    args = parser.parse_args()

    say = ""
    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            say = f.read()
    elif args.text:
        say = args.text

    say = say.strip()
    if not say:
        sys.stderr.write("ERROR: Empty text\n")
        sys.exit(1)

    comm = Communicate(say, args.voice, rate=args.rate, pitch=args.pitch)
    await comm.save(args.write_media)
    print(f"SUCCESS: {args.write_media}")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:
        sys.stderr.write(f"ERROR: {e}\n")
        sys.exit(1)
