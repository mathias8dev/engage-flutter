# Engage Flutter example

Run the example with an Engage App key:

```shell
flutter run --dart-define=ENGAGE_APP_KEY=eng_app_example
```

The App starts the SDK, observes the installation ID and opens the native
DivKit Message Center. Android uses the Engage snapshot artifacts from Maven
Local. iOS uses the sibling Engage Swift package through Swift Package Manager.
