// AWS SDK Interop
// Handles Cognito authentication and S3 uploads via pre-signed URLs

// Configuration
const AWS_CONFIG = {
    region: 'us-east-1',
    userPoolId: 'us-east-1_wslqPOxQd',
    clientId: '4tmf8s58738hrbrp4ff2utqg5',
    apiBaseUrl: 'https://api.epequeno.app'
};

window.AwsInterop = {
    setup: function(ports) {
        console.log('AWS Interop ready');

        // Handle session restoration requests
        if (ports.restoreSessionPort) {
            ports.restoreSessionPort.subscribe(async function() {
                try {
                    const result = await restoreAuthSession();
                    if (ports.receiveRestoredSession) {
                        ports.receiveRestoredSession.send(JSON.stringify(result));
                    }
                } catch (error) {
                    console.error('Session restoration error:', error);
                    if (ports.receiveRestoredSession) {
                        ports.receiveRestoredSession.send(JSON.stringify({
                            success: false,
                            error: error.message
                        }));
                    }
                }
            });
        }

        // Handle clear session requests
        if (ports.clearSessionPort) {
            ports.clearSessionPort.subscribe(function() {
                clearAuthSession();
            });
        }

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

        // Handle file upload requests from Elm (using pre-signed URLs)
        if (ports.uploadFilePort) {
            ports.uploadFilePort.subscribe(async function(request) {
                try {
                    console.log('Uploading file via pre-signed URL...', request);

                    // Get the file from the file input
                    const fileInput = document.getElementById('file-input');
                    if (!fileInput || !fileInput.files || fileInput.files.length === 0) {
                        throw new Error('No file selected');
                    }

                    const file = fileInput.files[0];

                    // Get pre-signed upload URL from API
                    const presignedData = await getPresignedUploadUrl(
                        request.accessToken,
                        file.name,
                        file.type || 'application/pdf'
                    );

                    // Upload file directly to pre-signed URL
                    await uploadToPresignedUrl(
                        file,
                        presignedData.upload_url,
                        presignedData.content_type,
                        ports.receiveUploadProgress
                    );

                    if (ports.receiveUploadResponse) {
                        ports.receiveUploadResponse.send(JSON.stringify({
                            success: true,
                            s3Key: presignedData.s3_key
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

// Get pre-signed upload URL from API
async function getPresignedUploadUrl(accessToken, filename, contentType) {
    const response = await fetch(
        `${AWS_CONFIG.apiBaseUrl}/v1/models/marker/upload-url`,
        {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                filename: filename,
                content_type: contentType
            })
        }
    );

    if (!response.ok) {
        const error = await response.text();
        throw new Error(`Failed to get upload URL: ${error}`);
    }

    return await response.json();
}

// Upload file to pre-signed URL (no AWS signing needed!)
async function uploadToPresignedUrl(file, presignedUrl, contentType, progressPort) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();

        // Progress tracking
        if (progressPort && xhr.upload) {
            xhr.upload.addEventListener('progress', (e) => {
                if (e.lengthComputable) {
                    const progress = e.loaded / e.total;
                    progressPort.send(progress);
                }
            });
        }

        xhr.addEventListener('load', () => {
            if (xhr.status >= 200 && xhr.status < 300) {
                resolve();
            } else {
                reject(new Error(`S3 upload failed with status ${xhr.status}`));
            }
        });

        xhr.addEventListener('error', () => {
            reject(new Error('Network error during upload'));
        });

        xhr.open('PUT', presignedUrl);
        xhr.setRequestHeader('Content-Type', contentType);
        xhr.send(file);
    });
}

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

// Cognito Authentication
async function authenticateWithCognito(email, password) {
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
    const refreshToken = authResult.AuthenticationResult.RefreshToken;
    const expiresIn = authResult.AuthenticationResult.ExpiresIn;

    // Calculate expiration timestamp
    const expiresAt = Date.now() + (expiresIn * 1000);

    const tokens = {
        success: true,
        accessToken: accessToken,
        idToken: idToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt
    };

    // Store tokens in localStorage
    localStorage.setItem('pdfmodels_auth', JSON.stringify({
        accessToken,
        idToken,
        refreshToken,
        expiresAt
    }));

    return tokens;
}

// Refresh access token using refresh token
async function refreshAuthToken(refreshToken) {
    const refreshParams = {
        AuthFlow: 'REFRESH_TOKEN_AUTH',
        ClientId: AWS_CONFIG.clientId,
        AuthParameters: {
            REFRESH_TOKEN: refreshToken
        }
    };

    const response = await fetch(
        `https://cognito-idp.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth'
            },
            body: JSON.stringify(refreshParams)
        }
    );

    if (!response.ok) {
        const error = await response.json();
        throw new Error(error.message || 'Token refresh failed');
    }

    const result = await response.json();
    return {
        accessToken: result.AuthenticationResult.AccessToken,
        idToken: result.AuthenticationResult.IdToken,
        expiresIn: result.AuthenticationResult.ExpiresIn
    };
}

// Load tokens from localStorage and refresh if needed
async function restoreAuthSession() {
    const stored = localStorage.getItem('pdfmodels_auth');
    if (!stored) {
        return { success: false, error: 'No stored session' };
    }

    try {
        const tokens = JSON.parse(stored);
        const now = Date.now();

        // Check if token is expired or will expire in next 5 minutes
        if (tokens.expiresAt - now < 5 * 60 * 1000) {
            console.log('Token expired or expiring soon, refreshing...');

            const refreshed = await refreshAuthToken(tokens.refreshToken);
            const newExpiresAt = now + (refreshed.expiresIn * 1000);

            const updatedTokens = {
                accessToken: refreshed.accessToken,
                idToken: refreshed.idToken,
                refreshToken: tokens.refreshToken,
                expiresAt: newExpiresAt
            };

            localStorage.setItem('pdfmodels_auth', JSON.stringify(updatedTokens));

            return {
                success: true,
                ...updatedTokens
            };
        }

        // Token still valid
        return {
            success: true,
            ...tokens
        };
    } catch (error) {
        console.error('Failed to restore session:', error);
        localStorage.removeItem('pdfmodels_auth');
        return { success: false, error: error.message };
    }
}

// Clear stored tokens on sign out
function clearAuthSession() {
    localStorage.removeItem('pdfmodels_auth');
}
