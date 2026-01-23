module Views.SignUp exposing (view)

{-| Sign Up page with split-screen layout matching Pencil design (D8HGD)

Left section: Hero with branding and testimonial (same as Login)
Right section: Sign up form (520px width)

-}

import Components.Button as Button
import Components.Checkbox as Checkbox
import Components.Input as Input
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, href, type_)
import Html.Styled.Events exposing (onClick, onSubmit)
import Styles
import Types exposing (..)


view : Model -> Html Msg
view model =
    if model.signUpForm.success then
        viewSuccess

    else if model.signUpForm.needsConfirmation then
        viewConfirmation model

    else
        viewSignUpPage model


{-| Main sign up page with split-screen layout
-}
viewSignUpPage : Model -> Html Msg
viewSignUpPage model =
    div
        [ css
            [ displayFlex
            , height (vh 100)
            , backgroundColor Styles.colors.background
            , overflow hidden
            ]
        ]
        [ -- Left: Hero section (same as Login)
          heroSection

        -- Right: Sign up form
        , formSection model
        ]


{-| Left hero section with branding and testimonial (same as Login page)
-}
heroSection : Html Msg
heroSection =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , justifyContent spaceBetween
            , flex (int 1)
            , height (pct 100)
            , padding (px 80)
            , backgroundColor Styles.colors.backgroundSidebar
            ]
        ]
        [ -- Top: Logo + Hero
          div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "48px"
                ]
            ]
            [ -- Logo
              logo

            -- Hero content
            , heroContent
            ]

        -- Bottom: Testimonial
        , testimonial
        ]


{-| Logo section
-}
logo : Html Msg
logo =
    div
        [ css
            [ displayFlex
            , alignItems center
            , property "gap" "12px"
            ]
        ]
        [ -- Logo mark
          div
            [ css
                [ width (px 36)
                , height (px 36)
                , border3 (px 1) solid Styles.colors.primary
                , borderRadius zero
                , flexShrink (int 0)
                ]
            ]
            []

        -- Logo text
        , span
            [ css
                [ fontFamilies Styles.displayFontStack
                , fontSize (px 22)
                , fontWeight (int 400)
                , color Styles.colors.foreground
                , letterSpacing (px 1)
                , lineHeight (num 1.2)
                ]
            ]
            [ text "PDF Models" ]
        ]


{-| Hero content section
-}
heroContent : Html Msg
heroContent =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "16px"
            , width (pct 100)
            ]
        ]
        [ -- Hero title
          h1
            [ css
                [ fontFamilies Styles.displayFontStack
                , fontSize (px 42)
                , fontWeight (int 400)
                , color Styles.colors.foreground
                , lineHeight (num 1.2)
                , margin zero
                , whiteSpace preWrap
                ]
            ]
            [ text "Process documents with\nAI-powered precision" ]

        -- Hero description
        , p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 16)
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                , lineHeight (num 1.6)
                , margin zero
                , maxWidth (px 400)
                ]
            ]
            [ text "Compare and evaluate multiple document processing models. Upload PDFs, select models, and download processed results." ]
        ]


{-| Testimonial section
-}
testimonial : Html Msg
testimonial =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "24px"
            , width (pct 100)
            ]
        ]
        [ -- Testimonial quote
          p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , fontStyle italic
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                , lineHeight (num 1.6)
                , margin zero
                , maxWidth (px 400)
                ]
            ]
            [ text "\"PDF Models has transformed how we evaluate document processing solutions. The comparison features saved us weeks of manual testing.\"" ]

        -- Author info
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "12px"
                ]
            ]
            [ -- Avatar
              div
                [ css
                    [ displayFlex
                    , alignItems center
                    , justifyContent center
                    , width (px 40)
                    , height (px 40)
                    , border3 (px 1) solid Styles.colors.borderEmphasis
                    , borderRadius zero
                    , flexShrink (int 0)
                    ]
                ]
                [ span
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 14)
                        , fontWeight (int 500)
                        , color Styles.colors.foreground
                        ]
                    ]
                    [ text "SK" ]
                ]

            -- Author details
            , div
                [ css
                    [ displayFlex
                    , flexDirection column
                    , property "gap" "2px"
                    ]
                ]
                [ div
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 13)
                        , fontWeight (int 500)
                        , color Styles.colors.foreground
                        ]
                    ]
                    [ text "Sarah Kim" ]
                , div
                    [ css
                        [ fontFamilies Styles.fontStack
                        , fontSize (px 11)
                        , fontWeight (int 400)
                        , color Styles.colors.foregroundSubtle
                        ]
                    ]
                    [ text "Data Engineer at TechCorp" ]
                ]
            ]
        ]


{-| Right form section
-}
formSection : Model -> Html Msg
formSection model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , alignItems center
            , justifyContent center
            , width (px 520)
            , height (pct 100)
            , padding2 (px 80) (px 60)
            ]
        ]
        [ signUpForm model
        ]


{-| Sign up form
-}
signUpForm : Model -> Html Msg
signUpForm model =
    Html.Styled.form
        [ onSubmit SignUpClicked
        , css
            [ displayFlex
            , flexDirection column
            , property "gap" "32px"
            , width (pct 100)
            ]
        ]
        [ -- Form header
          formHeader

        -- Form fields
        , formFields model

        -- Error messages
        , errorMessages model

        -- Actions
        , formActions model

        -- Footer
        , formFooter
        ]


{-| Form header
-}
formHeader : Html Msg
formHeader =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "8px"
            , width (pct 100)
            ]
        ]
        [ h1
            [ css
                [ fontFamilies Styles.displayFontStack
                , fontSize (px 32)
                , fontWeight (int 400)
                , color Styles.colors.foreground
                , margin zero
                ]
            ]
            [ text "Create an account" ]
        , p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                , margin zero
                ]
            ]
            [ text "Get started with PDF Models today" ]
        ]


{-| Form fields section
-}
formFields : Model -> Html Msg
formFields model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "20px"
            , width (pct 100)
            ]
        ]
        [ -- Email input
          Input.input
            { label = "Email address"
            , value = model.signUpForm.email
            , onInput = SignUpEmailChanged
            , inputType = "email"
            , placeholder = "name@company.com"
            , hasError = False
            , autocomplete = "username"
            }

        -- Password input
        , Input.password
            { label = "Password"
            , value = model.signUpForm.password
            , onInput = SignUpPasswordChanged
            , placeholder = "Create a strong password"
            , hasError = passwordMismatch model.signUpForm
            , autocomplete = "new-password"
            , showPassword = model.signUpForm.showPassword
            , togglePassword = ToggleSignUpPasswordVisibility
            }

        -- Confirm password input
        , Input.password
            { label = "Confirm password"
            , value = model.signUpForm.confirmPassword
            , onInput = SignUpConfirmPasswordChanged
            , placeholder = "Confirm your password"
            , hasError = passwordMismatch model.signUpForm
            , autocomplete = "new-password"
            , showPassword = model.signUpForm.showConfirmPassword
            , togglePassword = ToggleSignUpConfirmPasswordVisibility
            }

        -- Terms checkbox
        , div [ css [ width (pct 100) ] ]
            [ Checkbox.checkbox "I agree to the Terms of Service and Privacy Policy" model.signUpForm.termsAccepted TermsAcceptedChanged
            ]
        ]


{-| Error messages section
-}
errorMessages : Model -> Html Msg
errorMessages model =
    div []
        [ if passwordMismatch model.signUpForm then
            div
                [ css
                    [ backgroundColor Styles.colors.warningMuted
                    , border3 (px 1) solid Styles.colors.warning
                    , borderRadius zero
                    , padding (px 12)
                    , color Styles.colors.warning
                    , fontSize (px 13)
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
                        , borderRadius zero
                        , padding (px 12)
                        , color Styles.colors.error
                        , fontSize (px 13)
                        , marginTop (px 12)
                        ]
                    ]
                    [ text err ]

            Nothing ->
                text ""
        ]


{-| Form actions
-}
formActions : Model -> Html Msg
formActions model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "16px"
            , width (pct 100)
            ]
        ]
        [ -- Create account button
          (if model.auth == Authenticating then
            styled Html.Styled.button
                [ width (pct 100)
                , displayFlex
                , alignItems center
                , justifyContent center
                , padding2 (px 12) (px 24)
                , backgroundColor Styles.colors.border
                , color Styles.colors.foregroundSubtle
                , cursor notAllowed
                , opacity (num 0.5)
                , border zero
                , fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 500)
                ]
                [ Attr.disabled True
                , Attr.type_ "button"
                ]
                [ text "Creating account..." ]

           else
            styled Html.Styled.button
                [ width (pct 100)
                , displayFlex
                , alignItems center
                , justifyContent center
                , padding2 (px 12) (px 24)
                , backgroundColor Styles.colors.primary
                , color Styles.colors.primaryForeground
                , border zero
                , fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 500)
                , cursor pointer
                , Styles.transitions.base
                , hover
                    [ backgroundColor Styles.colors.accentHover
                    ]
                ]
                [ onClick SignUpClicked
                , Attr.type_ "submit"
                ]
                [ text "Create account" ]
          )

        -- Divider with "or"
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "16px"
                , width (pct 100)
                ]
            ]
            [ div
                [ css
                    [ flex (int 1)
                    , height (px 1)
                    , backgroundColor Styles.colors.border
                    ]
                ]
                []
            , span
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 12)
                    , fontWeight (int 400)
                    , color Styles.colors.foregroundSubtle
                    ]
                ]
                [ text "or" ]
            , div
                [ css
                    [ flex (int 1)
                    , height (px 1)
                    , backgroundColor Styles.colors.border
                    ]
                ]
                []
            ]

        -- Continue with Google button
        , styled Html.Styled.button
            [ width (pct 100)
            , displayFlex
            , alignItems center
            , justifyContent center
            , padding2 (px 12) (px 20)
            , backgroundColor transparent
            , color Styles.colors.foregroundSubtle
            , border3 (px 1) solid Styles.colors.borderButton
            , cursor notAllowed
            , opacity (num 0.5)
            , fontFamilies Styles.fontStack
            , fontSize (px 13)
            , fontWeight (int 500)
            ]
            [ Attr.disabled True
            , Attr.type_ "button"
            ]
            [ text "Continue with Google" ]
        ]


{-| Form footer
-}
formFooter : Html Msg
formFooter =
    div
        [ css
            [ displayFlex
            , justifyContent center
            , property "gap" "6px"
            , width (pct 100)
            ]
        ]
        [ span
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 400)
                , color Styles.colors.foregroundMuted
                ]
            ]
            [ text "Already have an account?" ]
        , a
            [ href (routeToPath Login)
            , css
                [ fontFamilies Styles.fontStack
                , fontSize (px 13)
                , fontWeight (int 500)
                , color Styles.colors.primary
                , textDecoration none
                , Styles.transitions.base
                , hover
                    [ textDecoration underline
                    ]
                ]
            ]
            [ text "Sign in" ]
        ]


{-| Confirmation view (email verification) - centered layout
-}
viewConfirmation : Model -> Html Msg
viewConfirmation model =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , minHeight (vh 100)
            , backgroundColor Styles.colors.background
            , padding Styles.spacing.xl
            ]
        ]
        [ div
            [ css
                [ maxWidth (px 420)
                , width (pct 100)
                ]
            ]
            [ confirmationForm model
            ]
        ]


{-| Confirmation form
-}
confirmationForm : Model -> Html Msg
confirmationForm model =
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


{-| Success view - centered layout
-}
viewSuccess : Html Msg
viewSuccess =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , minHeight (vh 100)
            , backgroundColor Styles.colors.background
            , padding Styles.spacing.xl
            ]
        ]
        [ successContent
        ]


{-| Success content
-}
successContent : Html Msg
successContent =
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.success
            , borderRadius Styles.radius.xl
            , padding Styles.spacing.xxl
            , textAlign center
            , maxWidth (px 420)
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
