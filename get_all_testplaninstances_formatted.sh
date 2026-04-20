#!/bin/bash

# Script to get all testplan instances from API
# Usage: ./get_all_testplaninstances_formatted.sh

# Load .env if present
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

if [ -z "$WEEBL_TOKEN" ]; then
    echo "Error: WEEBL_TOKEN not set (add it to .env)"
    exit 1
fi

if [ -z "$WEEBL_API_BASE" ]; then
    echo "Error: WEEBL_API_BASE not set (add it to .env)"
    exit 1
fi

TOKEN="$WEEBL_TOKEN"
API_BASE="$WEEBL_API_BASE"

# Initialize variables for pagination
OFFSET=0
LIMIT=100
TEMP_DIR="/tmp/testplaninstances_$$"
mkdir -p "$TEMP_DIR"

echo "Fetching testplan instances..." >&2

# Fetch all results using pagination
PAGE=0
while true; do
    RESPONSE=$(curl -s -H "Authorization: Token $TOKEN" "$API_BASE/testplaninstances/?limit=$LIMIT&offset=$OFFSET")
    
    # Check if curl succeeded
    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to API"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Check if response contains error
    if echo "$RESPONSE" | jq -e '.detail' > /dev/null 2>&1; then
        echo "Error: $(echo "$RESPONSE" | jq -r '.detail')"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Get the count and results
    COUNT=$(echo "$RESPONSE" | jq -r '.count')
    echo "$RESPONSE" | jq -r '.results[]' > "$TEMP_DIR/page_$PAGE.json"
    RESULTS_LENGTH=$(echo "$RESPONSE" | jq '.results | length')
    
    # Break if we've fetched all results
    OFFSET=$((OFFSET + LIMIT))
    PAGE=$((PAGE + 1))
    
    if [ $OFFSET -ge $COUNT ] || [ $RESULTS_LENGTH -eq 0 ]; then
        break
    fi
    
    echo "Fetched $OFFSET/$COUNT..." >&2
done

# Combine all results into one file
jq -s '.' "$TEMP_DIR"/page_*.json > /tmp/testplaninstances_response.json
TOTAL_COUNT=$(jq 'length' /tmp/testplaninstances_response.json)

# Generate report using Python for better JSON handling and sorting
python3 -c "
import json
from datetime import datetime
from collections import defaultdict

with open('/tmp/testplaninstances_response.json', 'r') as f:
    data = json.load(f)

# Filter for November 2025 onwards and Passed status
filtered_tpi = []
for tpi in data:
    created = tpi.get('created_at', '')

    if created:
        try:
            dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
            # Filter for November 2025 onwards
            if dt.year > 2025 or (dt.year == 2025 and dt.month >= 11):
                filtered_tpi.append(tpi)
        except:
            pass

# Group by product name
product_groups = defaultdict(list)
for tpi in filtered_tpi:
    created = tpi.get('created_at', '')
    
    # Get test plan name
    if tpi.get('test_plan') and tpi['test_plan'].get('name'):
        testplan_name = tpi['test_plan']['name']
    else:
        testplan_name = 'TPI-' + str(tpi.get('id', 'unknown'))
    
    # Get product name for grouping
    if tpi.get('product_under_test') and tpi['product_under_test'].get('product') and tpi['product_under_test']['product'].get('name'):
        product_group = tpi['product_under_test']['product']['name']
        # Group mysql and postgresql under dataplatforms
        if product_group in ['mysql', 'mysql-k8s', 'postgresql', 'postgresql-k8s']:
            product_group = 'dataplatforms'
        # Group maas and maas-region-api under maas
        elif product_group in ['maas', 'maas-region-api']:
            product_group = 'maas'
        # Rename k8s to canonical-k8s for better display
        elif product_group == 'k8s':
            product_group = 'canonical-k8s'
    else:
        product_group = 'other'
    
    # Get product full name
    if tpi.get('product_under_test') and tpi['product_under_test'].get('name'):
        product_name = tpi['product_under_test']['name']
        # Extract version info from product name
        import re
        # For deb packages with format like "1:3.7.0~rc1-17938..."
        deb_match = re.search(r'-deb-1?:?(\d+\.\d+\.\d+(?:~\w+)?)', product_name)
        if deb_match:
            product_name = deb_match.group(1)
        else:
            # For database charms
            if 'postgresql' in product_name or 'mysql' in product_name:
                rev_match = re.search(r'\((\d+)\)-(\d+(?:\.\d+)?)/(?:candidate|edge)', product_name)
                if rev_match:
                    revision = rev_match.group(1)
                    db_version = rev_match.group(2)
                    product_name = db_version + ' rev ' + revision
                else:
                    # Fallback
                    revision_match = re.search(r'\((\d+)\)', product_name)
                    if revision_match:
                        product_name = 'rev ' + revision_match.group(1)
            # For microstack/openstack-snap, extract version, revision and channel
            elif 'openstack-snap' in product_name:
                ms_match = re.search(r'openstack-snap-(\d+\.\d+(?:\.\d+)?)\((\d+)\)-[^/]+/(\S+)', product_name)
                if ms_match:
                    ms_version = ms_match.group(1)
                    revision = ms_match.group(2)
                    channel = ms_match.group(3)
                    product_name = ms_version + ' rev ' + revision + ' ' + channel
                else:
                    revision_match = re.search(r'\((\d+)\)', product_name)
                    if revision_match:
                        product_name = 'rev ' + revision_match.group(1)
            # For k8s charms, extract revision and version
            elif 'k8s-charm' in product_name:
                k8s_match = re.search(r'\((\d+)\)-(\d+\.\d+)/', product_name)
                if k8s_match:
                    revision = k8s_match.group(1)
                    k8s_version = k8s_match.group(2)
                    product_name = k8s_version + ' rev ' + revision
                else:
                    revision_match = re.search(r'\((\d+)\)', product_name)
                    if revision_match:
                        product_name = 'rev ' + revision_match.group(1)
            else:
                # Try to extract version pattern for snaps and others
                version_match = re.search(r'-(\d+\.\d+(?:\.\d+)?(?:~\w+)?)', product_name)
                if version_match:
                    product_name = version_match.group(1)
                else:
                    # Try other patterns like revision numbers
                    revision_match = re.search(r'\((\d+)\)', product_name)
                    if revision_match:
                        product_name = 'rev ' + revision_match.group(1)
    else:
        product_name = ''
    
    # Format date
    try:
        dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
        date_formatted = dt.strftime('%Y-%m-%d')
    except:
        date_formatted = created
    
    # Get status
    if tpi.get('status') and tpi['status'].get('name'):
        status = tpi['status']['name']
    else:
        status = 'N/A'

    product_groups[product_group].append({
        'date': created,
        'date_formatted': date_formatted,
        'testplan_name': testplan_name,
        'product_name': product_name,
        'status': status,
    })

# Sort groups by product name and sort items within each group by date
import re

for product in sorted(product_groups.keys()):
    # Capitalize for display with special handling
    if product == 'canonical-k8s':
        display_name = 'Canonical k8s'
    elif product == 'dataplatforms':
        display_name = 'Dataplatforms'
    elif product == 'other':
        display_name = 'Other'
    else:
        # Uppercase first letter (MAAS, Juju, etc)
        display_name = product.upper() if len(product) <= 4 else product.capitalize()
    
    print(display_name)
    
    items = sorted(product_groups[product], key=lambda x: x['date'])
    for item in items:
        # Clean up testplan name and extract version info if needed
        testplan = item['testplan_name']
        version = item['product_name']
        
        print(f\"{item['date_formatted']}  {item['status']:<12}  {testplan}  {version}\")
    
    print()
"

# Clean up temp files
rm -f /tmp/testplaninstances_response.json
rm -rf "$TEMP_DIR"
