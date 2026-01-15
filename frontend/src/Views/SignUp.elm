module Views.SignUp exposing (view)

import Components.Button as Button
import Components.Input as Input
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href, type_)
import Html.Styled.Events exposing (onSubmit)
import Styles
import Types exposing (..)


view : Model -> Html Msg
view model =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , minHeight (vh 100)
            , padding Styles.spacing.xl
            ]
        ]
        [ div
            [ css
                [ maxWidth (px 420)
                , width (pct 100)
                ]
            ]
            [ -- Logo/Brand
              div
                [ css
                    [ textAlign center
                    , marginBottom Styles.spacing.xxl
                    ]
                ]
                [ div
                    [ css
                        [ Css.fontSize (px 48)
                        , marginBottom Styles.spacing.md
                        ]
                    ]
                    [ text "📄" ]
                , h1
                    [ css
                        [ Styles.textDisplay
                        , marginBottom Styles.spacing.xs
                        ]
                    ]
                    [ text "PDF Models" ]
                , p
                    [ css
                        [ Styles.textSecondary
                        , margin zero
                        ]
                    ]
                    [ text "Document processing platform" ]
                ]
            , if model.signUpForm.success then
                viewSuccess

              else if model.signUpForm.needsConfirmation then
                viewConfirmation model

              else
                viewForm model
            ]
        ]


viewForm : Model -> Html Msg
viewForm model =
    Html.Styled.form
        [ onSubmit SignUpClicked
        , css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.xl
            , padding Styles.spacing.xxl
            ]
        ]
        [ h2
            [ css
                [ Styles.textH1
                , marginBottom Styles.spacing.xl
                , textAlign center
                ]
            ]
            [ text "Create Account" ]
        , Input.input
            { label = "Email"
            , value = model.signUpForm.email
            , onInput = SignUpEmailChanged
            , inputType = "email"
            , placeholder = "you@example.com"
            , hasError = False
            , autocomplete = "username"
            }
        , Input.input
            { label = "Password"
            , value = model.signUpForm.password
            , onInput = SignUpPasswordChanged
            , inputType = "password"
            , placeholder = "Create a strong password"
            , hasError = passwordMismatch model.signUpForm
            , autocomplete = "new-password"
            }
        , Input.input
            { label = "Confirm Password"
            , value = model.signUpForm.confirmPassword
            , onInput = SignUpConfirmPasswordChanged
            , inputType = "password"
            , placeholder = "Confirm your password"
            , hasError = passwordMismatch model.signUpForm
            , autocomplete = "new-password"
            }
        , if passwordMismatch model.signUpForm then
            div
                [ css
                    [ backgroundColor Styles.colors.warningMuted
                    , border3 (px 1) solid Styles.colors.warning
                    , borderRadius Styles.radius.md
                    , padding Styles.spacing.md
                    , marginBottom Styles.spacing.lg
                    , color Styles.colors.warning
                    , Css.fontSize Styles.fontSize.small
                    ]
                ]
                [ text "Passwords do not match" ]

          else
            text ""
        , case model.signUpForm.error of
            Just err ->
                div
                    [ css
                        [ backgroundColor Styles.colors.errorMuted
                        , border3 (px 1) solid Styles.colors.error
                        , borderRadius Styles.radius.md
                        , padding Styles.spacing.md
                        , marginBottom Styles.spacing.lg
                        , color Styles.colors.error
                        , Css.fontSize Styles.fontSize.small
                        ]
                    ]
                    [ text err ]

            Nothing ->
                text ""
        , div [ css [ marginTop Styles.spacing.lg ] ]
            [ Html.Styled.button
                [ type_ "submit"
                , css
                    [ Css.width (pct 100)
                    , padding Styles.spacing.md
                    , backgroundColor Styles.colors.accent
                    , border zero
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textInverse
                    , fontWeight Styles.fontWeights.medium
                    , Css.fontSize Styles.fontSize.body
                    , cursor pointer
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.accentHover
                        ]
                    , focus
                        [ Styles.focusRing
                        ]
                    ]
                ]
                [ text
                    (if model.auth == Authenticating then
                        "Creating account..."

                     else
                        "Create Account"
                    )
                ]
            ]
        , div
            [ css
                [ marginTop Styles.spacing.xl
                , textAlign center
                , Styles.textSmall
                ]
            ]
            [ text "Already have an account? "
            , a
                [ href (routeToPath Login)
                , css
                    [ color Styles.colors.accent
                    , textDecoration none
                    , fontWeight Styles.fontWeights.medium
                    , Styles.transitions.base
                    , hover
                        [ color Styles.colors.accentHover
                        , textDecoration underline
                        ]
                    ]
                ]
                [ text "Sign in" ]
            ]
        ]


viewConfirmation : Model -> Html Msg
viewConfirmation model =
    Html.Styled.form
        [ onSubmit ConfirmSignUpClicked
        , css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.xl
            , padding Styles.spacing.xxl
            ]
        ]
        [ div
            [ css
                [ textAlign center
                , marginBottom Styles.spacing.xl
                ]
            ]
            [ div
                [ css
                    [ Css.fontSize (px 40)
                    , marginBottom Styles.spacing.md
                    ]
                ]
                [ text "📬" ]
            , h2
                [ css
                    [ Styles.textH1
                    , marginBottom Styles.spacing.sm
                    ]
                ]
                [ text "Check Your Email" ]
            , p
                [ css
                    [ Styles.textSecondary
                    , lineHeight Styles.lineHeights.relaxed
                    ]
                ]
                [ text "We've sent a confirmation code to "
                , span
                    [ css
                        [ color Styles.colors.accent
                        , fontWeight Styles.fontWeights.medium
                        ]
                    ]
                    [ text model.signUpForm.email ]
                ]
            ]
        , Input.input
            { label = "Confirmation Code"
            , value = model.signUpForm.confirmationCode
            , onInput = ConfirmationCodeChanged
            , inputType = "text"
            , placeholder = "Enter 6-digit code"
            , hasError = False
            , autocomplete = "off"
            }
        , case model.signUpForm.error of
            Just err ->
                div
                    [ css
                        [ backgroundColor Styles.colors.errorMuted
                        , border3 (px 1) solid Styles.colors.error
                        , borderRadius Styles.radius.md
                        , padding Styles.spacing.md
                        , marginBottom Styles.spacing.lg
                        , color Styles.colors.error
                        , Css.fontSize Styles.fontSize.small
                        ]
                    ]
                    [ text err ]

            Nothing ->
                text ""
        , div [ css [ marginTop Styles.spacing.lg ] ]
            [ Html.Styled.button
                [ type_ "submit"
                , css
                    [ Css.width (pct 100)
                    , padding Styles.spacing.md
                    , backgroundColor Styles.colors.accent
                    , border zero
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textInverse
                    , fontWeight Styles.fontWeights.medium
                    , Css.fontSize Styles.fontSize.body
                    , cursor pointer
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.accentHover
                        ]
                    , focus
                        [ Styles.focusRing
                        ]
                    ]
                ]
                [ text
                    (if model.signUpForm.confirming then
                        "Verifying..."

                     else
                        "Verify Account"
                    )
                ]
            ]
        ]


viewSuccess : Html Msg
viewSuccess =
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.success
            , borderRadius Styles.radius.xl
            , padding Styles.spacing.xxl
            , textAlign center
            ]
        ]
        [ div
            [ css
                [ Css.fontSize (px 48)
                , marginBottom Styles.spacing.md
                ]
            ]
            [ text "✓" ]
        , h2
            [ css
                [ Styles.textH1
                , color Styles.colors.success
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text "Account Verified" ]
        , p
            [ css
                [ Styles.textSecondary
                , marginBottom Styles.spacing.xl
                , lineHeight Styles.lineHeights.relaxed
                ]
            ]
            [ text "Your email has been verified. You can now sign in and start processing documents." ]
        , a
            [ href (routeToPath Login)
            , css
                [ display inlineBlock
                , padding2 Styles.spacing.md Styles.spacing.xl
                , backgroundColor Styles.colors.accent
                , borderRadius Styles.radius.md
                , color Styles.colors.textInverse
                , textDecoration none
                , fontWeight Styles.fontWeights.medium
                , Css.fontSize Styles.fontSize.body
                , Styles.transitions.base
                , hover
                    [ backgroundColor Styles.colors.accentHover
                    ]
                ]
            ]
            [ text "Continue to Sign In" ]
        ]


passwordMismatch : SignUpForm -> Bool
passwordMismatch form =
    not (String.isEmpty form.password)
        && not (String.isEmpty form.confirmPassword)
        && form.password
        /= form.confirmPassword
