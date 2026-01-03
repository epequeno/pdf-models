#!/bin/bash
set -e

# Build script for PDF Models frontend
# Compiles Elm and bundles all assets into dst/ folder

cd "$(dirname "$0")"

echo "Building PDF Models frontend..."

# Clean and create dst directory
rm -rf dst
mkdir -p dst

# Compile Elm to JavaScript
echo "Compiling Elm..."
elm make src/Main.elm --optimize --output=dst/main.js

# Create index.html
echo "Creating index.html..."
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

        // Wire up ports for AWS SDK interop when needed
        if (window.AwsInterop && app.ports) {
            window.AwsInterop.setup(app.ports);
        }
    </script>
</body>
</html>
EOF

# Create interop.js for AWS SDK
echo "Creating interop.js..."
cat > dst/interop.js << 'EOF'
// AWS SDK Interop
// Handles Cognito authentication and S3 uploads

// Configuration - TODO: Move to env variables for production
const AWS_CONFIG = {
    region: 'us-east-1',
    userPoolId: 'us-east-1_wslqPOxQd',
    clientId: '4tmf8s58738hrbrp4ff2utqg5',
    identityPoolId: 'us-east-1:1fd26b6e-8a1c-4dd7-940d-60ec7884f384',
    s3Bucket: 'pdf-models-docs-496830984285'
};

window.AwsInterop = {
    setup: function(ports) {
        console.log('AWS Interop ready');

        if (!ports.signInPort) {
            console.warn('signInPort not found');
            return;
        }

        // Handle sign in requests from Elm
        ports.signInPort.subscribe(async function(credentials) {
            try {
                console.log('Attempting sign in...');
                const result = await authenticateWithCognito(
                    credentials.email,
                    credentials.password
                );

                if (ports.receiveAuthResponse) {
                    ports.receiveAuthResponse.send(JSON.stringify(result));
                }
            } catch (error) {
                console.error('Authentication error:', error);
                if (ports.receiveAuthResponse) {
                    ports.receiveAuthResponse.send(JSON.stringify({
                        success: false,
                        error: error.message || 'Authentication failed'
                    }));
                }
            }
        });

        // Handle sign up requests from Elm
        if (ports.signUpPort) {
            ports.signUpPort.subscribe(async function(credentials) {
                try {
                    console.log('Attempting sign up...');
                    const result = await signUpWithCognito(
                        credentials.email,
                        credentials.password
                    );

                    if (ports.receiveSignUpResponse) {
                        ports.receiveSignUpResponse.send(JSON.stringify(result));
                    }
                } catch (error) {
                    console.error('Sign up error:', error);
                    if (ports.receiveSignUpResponse) {
                        ports.receiveSignUpResponse.send(JSON.stringify({
                            success: false,
                            userConfirmed: false,
                            error: error.message || 'Sign up failed'
                        }));
                    }
                }
            });
        }

        // Handle confirm sign up requests from Elm
        if (ports.confirmSignUpPort) {
            ports.confirmSignUpPort.subscribe(async function(data) {
                try {
                    console.log('Attempting to confirm sign up...');
                    const result = await confirmSignUpWithCognito(
                        data.email,
                        data.code
                    );

                    if (ports.receiveConfirmSignUpResponse) {
                        ports.receiveConfirmSignUpResponse.send(JSON.stringify(result));
                    }
                } catch (error) {
                    console.error('Confirm sign up error:', error);
                    if (ports.receiveConfirmSignUpResponse) {
                        ports.receiveConfirmSignUpResponse.send(JSON.stringify({
                            success: false,
                            error: error.message || 'Confirmation failed'
                        }));
                    }
                }
            });
        }

        // Handle file upload requests from Elm
        if (ports.uploadFilePort) {
            ports.uploadFilePort.subscribe(async function(request) {
                try {
                    console.log('Uploading file to S3...', request);
                    const s3Key = `${request.identityId}/${request.jobId}.pdf`;

                    // For MVP, we'll need the AWS SDK to upload to S3
                    // Placeholder response for now
                    if (ports.receiveUploadResponse) {
                        ports.receiveUploadResponse.send(JSON.stringify({
                            success: true,
                            s3Key: s3Key
                        }));
                    }
                } catch (error) {
                    console.error('Upload error:', error);
                    if (ports.receiveUploadResponse) {
                        ports.receiveUploadResponse.send(JSON.stringify({
                            success: false,
                            error: error.message || 'Upload failed'
                        }));
                    }
                }
            });
        }
    }
};

// Cognito Sign Up
async function signUpWithCognito(email, password) {
    const signUpParams = {
        ClientId: AWS_CONFIG.clientId,
        Username: email,
        Password: password,
        UserAttributes: [
            {
                Name: 'email',
                Value: email
            }
        ]
    };

    const response = await fetch(
        `https://cognito-idp.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityProviderService.SignUp'
            },
            body: JSON.stringify(signUpParams)
        }
    );

    if (!response.ok) {
        const error = await response.json();
        throw new Error(error.message || error.__type || 'Sign up failed');
    }

    const result = await response.json();

    return {
        success: true,
        userConfirmed: result.UserConfirmed || false
    };
}

// Cognito Confirm Sign Up
async function confirmSignUpWithCognito(email, code) {
    const confirmParams = {
        ClientId: AWS_CONFIG.clientId,
        Username: email,
        ConfirmationCode: code
    };

    const response = await fetch(
        `https://cognito-idp.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityProviderService.ConfirmSignUp'
            },
            body: JSON.stringify(confirmParams)
        }
    );

    if (!response.ok) {
        const error = await response.json();
        throw new Error(error.message || error.__type || 'Confirmation failed');
    }

    return {
        success: true
    };
}

// Cognito Authentication (using fetch API, no AWS SDK needed)
async function authenticateWithCognito(email, password) {
    // Step 1: Authenticate with Cognito User Pool
    const authParams = {
        AuthFlow: 'USER_PASSWORD_AUTH',
        ClientId: AWS_CONFIG.clientId,
        AuthParameters: {
            USERNAME: email,
            PASSWORD: password
        }
    };

    const cognitoResponse = await fetch(
        `https://cognito-idp.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth'
            },
            body: JSON.stringify(authParams)
        }
    );

    if (!cognitoResponse.ok) {
        const error = await cognitoResponse.json();
        throw new Error(error.message || error.__type || 'Authentication failed');
    }

    const authResult = await cognitoResponse.json();
    const idToken = authResult.AuthenticationResult.IdToken;
    const accessToken = authResult.AuthenticationResult.AccessToken;

    // Step 2: Get Identity ID from Identity Pool
    const identityParams = {
        IdentityPoolId: AWS_CONFIG.identityPoolId,
        Logins: {
            [`cognito-idp.${AWS_CONFIG.region}.amazonaws.com/${AWS_CONFIG.userPoolId}`]: idToken
        }
    };

    const identityResponse = await fetch(
        `https://cognito-identity.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityService.GetId'
            },
            body: JSON.stringify(identityParams)
        }
    );

    if (!identityResponse.ok) {
        throw new Error('Failed to get identity ID');
    }

    const identityResult = await identityResponse.json();
    const identityId = identityResult.IdentityId;

    return {
        success: true,
        accessToken: accessToken,
        idToken: idToken,
        identityId: identityId
    };
}
EOF

echo "Build complete! Output in dst/"
echo "To serve locally: cd dst && python3 -m http.server 8000"
