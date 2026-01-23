#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building PDF Models frontend..."

# Clean and create dst directory
rm -rf dst
mkdir -p dst

# Compile Elm to JavaScript
elm make src/Main.elm --optimize --output=dst/main.js

# Create index.html
cat > dst/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PDF Models</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
    </style>
</head>
<body>
    <div id="app"></div>
    <script src="interop.js"></script>
    <script src="main.js"></script>
    <script>
        var app = Elm.Main.init({
            node: document.getElementById('app'),
            flags: {}
        });

        if (window.AwsInterop && app.ports) {
            window.AwsInterop.setup(app.ports);
        }
    </script>
</body>
</html>
EOF

# Copy interop.js
cp interop.js dst/interop.js

echo "Build complete! Output in dst/"
echo "To serve locally: cd dst && python3 -m http.server 8000"
