curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
chmod +x cloudflared

TARGET_URL="http://127.0.0.1:7860"
LOG_FILE="tunnel.log"

while true; do
    echo "--- Starting Cloudflare Tunnel ---"
    rm -f $LOG_FILE
    ./cloudflared tunnel --no-autoupdate --protocol auto --url $TARGET_URL > $LOG_FILE 2>&1 &
    TUNNEL_PID=$!

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

    SUCCESS=false
    for i in {1..10}; do
        curl -s -I "$TUNNEL_URL" > /dev/null
        CURL_EXIT_STATUS=$?

        if [ $CURL_EXIT_STATUS -eq 0 ] || [ $CURL_EXIT_STATUS -eq 22 ]; then
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
        wait $TUNNEL_PID
    else
        echo "❌ Tunnel failed to stabilize. Killing and retrying from scratch..."
        kill $TUNNEL_PID
        sleep 2
    fi
done
