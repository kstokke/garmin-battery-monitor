# Garmin battery monitor

Checks sensor batteries from the latest Garmin activity and optionally sends
low-battery alerts to an ntfy topic supplied on the command line.

## Daily GitHub Action

1. Under **Settings → Environments**, create or open the `Garmin` environment.
2. Add an environment secret named `GARMIN_API_KEY` containing the Garmin personal
   API key (the value stored locally at `external/garmin` in gopass).
3. Add an environment variable named `NTFY_TOPIC` containing your ntfy.sh topic
   name (without the server URL).
4. Push the workflow and script to the repository's default branch.

The workflow job references the `Garmin` environment to access these values.

The workflow runs daily at 06:17 UTC with notifications enabled. You can also
start it manually from **Actions → Garmin battery monitor → Run workflow**.
Each run checks the latest activity, so a low battery can produce another alert
on subsequent days until the latest activity reports otherwise.

## Local use

```sh
ruby garmin-battery-monitor.rb
ruby garmin-battery-monitor.rb --ntfy-topic your-topic
```

Set `GARMIN_API_KEY` in the environment, or leave it unset to read the key from
`gopass show external/garmin`. The script uses only Ruby standard libraries.
