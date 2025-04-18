program Example_FCM;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils, FCM.Helper;

begin
  try
    var Response := TFCMHelper.SendPushNotification(
      'Path to the Firebase service account JSON key file',
      'Device Token',
      'Your Project ID',
      'Title',
      'Hello, World'
    );

    Writeln(Response);

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
