#!/usr/bin/env python3

from xlr_lib import bot_warfare_enabled, load_config, sync_bots_txt


def main():
    config = load_config()
    if not bot_warfare_enabled(config):
        print("[bot_names] Bot Warfare disabled — skipped")
        return
    count = sync_bots_txt(config=config)
    print(f"[bot_names] wrote {count} entries to bots.txt")


if __name__ == "__main__":
    main()
