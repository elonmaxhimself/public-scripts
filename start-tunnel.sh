TARGET_URL="http://127.0.0.1:5000"
LOG_FILE="tunnel.log"

while true; do
    echo "--- Starting Cloudflare Tunnel ---"
    # Clear old logs and start cloudflared in the background
    rm -f $LOG_FILE
    ./cloudflared tunnel --no-autoupdate --protocol auto --url $TARGET_URL > $LOG_FILE 2>&1 &
    TUNNEL_PID=$!

    # Wait for the URL to appear in the logs (timeout after 15s)
    echo "Waiting for URL generation..."
    for i in {1..15}; do
        TUNNEL_URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.trycloudflare\.com" $LOG_FILE | head -n 1)
        if [ ! -z "$TUNNEL_URL" ]; then break; fi
        sleep 1
    done

    if [ -z "$TUNNEL_URL" ]; then
        echo "Failed to get URL from logs. Restarting..."
        kill $TUNNEL_PID
        continue
    fi

    echo "Generated URL: $TUNNEL_URL"
    echo "Testing DNS propagation..."

    # Test the URL for up to 30 seconds
    SUCCESS=false
    for i in {1..10}; do
        # We check if curl can resolve the host (exit code 6 is "Could not resolve host")
        # -s: silent, -o: ignore body, -I: headers only
        curl -s -I "$TUNNEL_URL" > /dev/null
        CURL_EXIT_STATUS=$?

        if [ $CURL_EXIT_STATUS -eq 0 ] || [ $CURL_EXIT_STATUS -eq 22 ]; then
            # Exit 22 can happen if it's a 404/5xx, but it means the host RESOLVED
            echo "✅ Tunnel is LIVE at $TUNNEL_URL"
            SUCCESS=true
            break
        elif [ $CURL_EXIT_STATUS -eq 6 ]; then
            echo "... DNS not ready yet (Attempt $i/10)"
        else
            echo "... Connection issue (Error $CURL_EXIT_STATUS), retrying..."
        fi
        sleep 3
    done

    if [ "$SUCCESS" = true ]; then
        # Keep the script running so the background tunnel stays alive
        wait $TUNNEL_PID
    else
        echo "❌ Tunnel failed to stabilize. Killing and retrying from scratch..."
        kill $TUNNEL_PID
        sleep 2
    fi
done
