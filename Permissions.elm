port module Permissions exposing
    ( PermissionStatus(..)
    , onPermissionChange
    , permissionStatus
    , permissionStatusString
    , requestPermission
    )


type PermissionStatus
    = Granted
    | Denied
    | Prompt


onPermissionChange : (PermissionStatus -> msg) -> Sub msg
onPermissionChange msg =
    onPermissionChangeInternal (permissionStatus >> msg)


port onPermissionChangeInternal : (String -> msg) -> Sub msg


port requestPermissionInternal : () -> Cmd msg


requestPermission : Cmd msg
requestPermission =
    requestPermissionInternal ()


permissionStatus : String -> PermissionStatus
permissionStatus s =
    case s of
        "denied" ->
            Denied

        "granted" ->
            Granted

        _ ->
            Prompt


permissionStatusString : PermissionStatus -> String
permissionStatusString ps =
    case ps of
        Granted ->
            "granted"

        Denied ->
            "denied"

        Prompt ->
            "prompt"
