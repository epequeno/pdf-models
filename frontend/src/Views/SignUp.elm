module Views.SignUp exposing (view)

import Components.Button as Button
import Components.Input as Input
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
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
            ]
        ]
        [ div
            [ css
                [ maxWidth (px 400)
                , width (pct 100)
                , padding Styles.spacing.xl
                ]
            ]
            [ h1
                [ css
                    [ Css.fontSize Styles.fontSize.h1
                    , fontWeight Styles.fontWeight.semibold
                    , marginBottom Styles.spacing.xl
                    , textAlign center
                    , color Styles.colors.textPrimary
                    ]
                ]
                [ text "PDF Models" ]
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
            [ border3 (px 1) solid Styles.colors.border
            , padding Styles.spacing.lg
            , backgroundColor Styles.colors.surface
            ]
        ]
        [ h2
            [ css
                [ Css.fontSize Styles.fontSize.h2
                , fontWeight Styles.fontWeight.semibold
                , marginBottom Styles.spacing.lg
                , color Styles.colors.textPrimary
                ]
            ]
            [ text "Create Account" ]
        , Input.input
            { label = "Email"
            , value = model.signUpForm.email
            , onInput = SignUpEmailChanged
            , inputType = "email"
            , placeholder = "your@email.com"
            , hasError = False
            , autocomplete = "username"
            }
        , Input.input
            { label = "Password"
            , value = model.signUpForm.password
            , onInput = SignUpPasswordChanged
            , inputType = "password"
            , placeholder = "••••••••"
            , hasError = passwordMismatch model.signUpForm
            , autocomplete = "new-password"
            }
        , Input.input
            { label = "Confirm Password"
            , value = model.signUpForm.confirmPassword
            , onInput = SignUpConfirmPasswordChanged
            , inputType = "password"
            , placeholder = "••••••••"
            , hasError = passwordMismatch model.signUpForm
            , autocomplete = "new-password"
            }
        , if passwordMismatch model.signUpForm then
            div
                [ css
                    [ color Styles.colors.accentError
                    , Css.fontSize Styles.fontSize.small
                    , marginBottom Styles.spacing.sm
                    ]
                ]
                [ text "Passwords do not match" ]

          else
            text ""
        , case model.signUpForm.error of
            Just err ->
                div
                    [ css
                        [ color Styles.colors.accentError
                        , Css.fontSize Styles.fontSize.small
                        , marginBottom Styles.spacing.sm
                        ]
                    ]
                    [ text err ]

            Nothing ->
                text ""
        , div [ css [ marginTop Styles.spacing.md ] ]
            [ Button.button Button.Primary
                (if model.auth == Authenticating then
                    "Creating account..."

                 else
                    "Sign Up"
                )
                SignUpClicked
            ]
        , div
            [ css
                [ marginTop Styles.spacing.md
                , textAlign center
                , Css.fontSize Styles.fontSize.small
                , color Styles.colors.textSecondary
                ]
            ]
            [ text "Already have an account? "
            , a
                [ href "/login"
                , css
                    [ color Styles.colors.accentPrimary
                    , textDecoration none
                    , hover [ textDecoration underline ]
                    ]
                ]
                [ text "Sign In" ]
            ]
        ]


viewConfirmation : Model -> Html Msg
viewConfirmation model =
    Html.Styled.form
        [ onSubmit ConfirmSignUpClicked
        , css
            [ border3 (px 1) solid Styles.colors.border
            , padding Styles.spacing.lg
            , backgroundColor Styles.colors.surface
            ]
        ]
        [ h2
            [ css
                [ Css.fontSize Styles.fontSize.h2
                , fontWeight Styles.fontWeight.semibold
                , marginBottom Styles.spacing.lg
                , color Styles.colors.textPrimary
                ]
            ]
            [ text "Check Your Email" ]
        , p
            [ css
                [ color Styles.colors.textSecondary
                , marginBottom Styles.spacing.md
                , lineHeight (num 1.6)
                ]
            ]
            [ text "We've sent a confirmation code to "
            , span [ css [ color Styles.colors.textPrimary, fontWeight Styles.fontWeight.semibold ] ]
                [ text model.signUpForm.email ]
            , text ". Enter the code below to verify your account."
            ]
        , Input.input
            { label = "Confirmation Code"
            , value = model.signUpForm.confirmationCode
            , onInput = ConfirmationCodeChanged
            , inputType = "text"
            , placeholder = "123456"
            , hasError = False
            , autocomplete = "off"
            }
        , case model.signUpForm.error of
            Just err ->
                div
                    [ css
                        [ color Styles.colors.accentError
                        , Css.fontSize Styles.fontSize.small
                        , marginTop Styles.spacing.sm
                        , marginBottom Styles.spacing.sm
                        ]
                    ]
                    [ text err ]

            Nothing ->
                text ""
        , div [ css [ marginTop Styles.spacing.md ] ]
            [ Button.button Button.Primary
                (if model.signUpForm.confirming then
                    "Confirming..."

                 else
                    "Confirm Account"
                )
                ConfirmSignUpClicked
            ]
        ]


viewSuccess : Html Msg
viewSuccess =
    div
        [ css
            [ border3 (px 1) solid Styles.colors.accentSuccess
            , padding Styles.spacing.lg
            , backgroundColor Styles.colors.surface
            ]
        ]
        [ h2
            [ css
                [ Css.fontSize Styles.fontSize.h2
                , fontWeight Styles.fontWeight.semibold
                , marginBottom Styles.spacing.md
                , color Styles.colors.accentSuccess
                ]
            ]
            [ text "Account Confirmed!" ]
        , p
            [ css
                [ color Styles.colors.textPrimary
                , marginBottom Styles.spacing.md
                , lineHeight (num 1.6)
                ]
            ]
            [ text "Your email has been verified. You can now sign in with your credentials." ]
        , a
            [ href "/login"
            , css
                [ display inlineBlock
                , padding2 Styles.spacing.sm Styles.spacing.md
                , border3 (px 1) solid Styles.colors.accentPrimary
                , color Styles.colors.accentPrimary
                , textDecoration none
                , fontFamilies Styles.fontStack
                , Css.fontSize Styles.fontSize.body
                , hover [ backgroundColor Styles.colors.hover ]
                ]
            ]
            [ text "Go to Sign In" ]
        ]


passwordMismatch : SignUpForm -> Bool
passwordMismatch form =
    not (String.isEmpty form.password)
        && not (String.isEmpty form.confirmPassword)
        && form.password
        /= form.confirmPassword
