{
  *****************************************************************************
   Unit        : uresourceexe
   Author      : NEUTS JL
   License     : GPL (GNU General Public License)
   Date        : 10/02/2025
   Version     : V1.2.0

   Description : LAZARUS library to add resources to an executable

   This program is free software: you can redistribute it and/or modify it
   under the terms of the GNU General Public License as published by the Free
   Software Foundation, either version 3 of the License, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
   Public License for more details.

   You should have received a copy of the GNU General Public License along with
   this program. If not, see <https://www.gnu.org/licenses/>.
  *****************************************************************************
}

unit uresourceexe;

{$mode ObjFPC}{$H+}

interface
uses
  classes, sysutils, fgl, fileutil;

Type
  TResource=class
    Name:string;
    FileName:String;
  end;
  TResources=specialize TFPGList<TResource>;

  TResourceExeBuilder=Class
    FResources:TResources;
  public
    constructor Create;
    destructor Destroy;override;
    procedure Clear;
    procedure AddFromFile(Const ResourceFile:String);
    procedure AddFromFile(Const ResourceName,ResourceFile:String); overload;
    procedure ApplyToExe(Const ExeFileSrc, ExeFileDest:string);
  end;

  TResourceExeReader=Class
  private
    FExeFile:string;
    FResources:TStringList;
    procedure SetExeFile(Value:string);
    function GetCount:integer;
  public
    constructor Create;
    destructor Destroy;override;
    procedure List(AList:TStrings);
    function  ResourceExists(Const ResourceName:string):boolean;
    procedure SaveToDir(Const Dir:string);
    procedure SaveToFile(Const ResourceFile:string);
    procedure SaveToFile(Const ResourceName:string;Const ResourceFile:string);
    function  SaveToString(Const ResourceName:string):string;
    procedure SaveToString(Const ResourceName:string;var Content:string);
    procedure SaveToStream(Const ResourceName:string;S:TStream);
    property  Count:integer read GetCount;
    property  ExeFile:string read FExeFile write SetExeFile;
  end;

implementation

type
  THeader=record
    Name:String[127];
    Size:Int64;
    Last:boolean;
    Filler:Array[127+8+1..255] of Byte;
  end;

constructor TResourceExeBuilder.Create;
begin
  FResources:=TResources.Create;
end;

destructor TResourceExeBuilder.Destroy;
begin
  FResources.Free;
  inherited;
end;

procedure TResourceExeBuilder.Clear;
begin
  FResources.Clear;
end;

procedure TResourceExeBuilder.AddFromFile(Const ResourceName,ResourceFile:String);
var
  i:integer;
  FResource:TResource;
begin
  for i:=0 to FResources.Count-1 do
    if UpperCase(FResources[i].Name)=UpperCase(ResourceName) then
    Raise Exception.Create('File already added : '+#13#10+ResourceName);
  FResource:=TResource.Create;
  FResource.FileName:=ResourceFile;
  FResource.Name:=ResourceName;
  FResources.Add(FResource);
end;

procedure TResourceExeBuilder.AddFromFile(Const ResourceFile:String);
begin
  AddFromFile(ExtractFileName(ResourceFile),ResourceFile);
end;

procedure TResourceExeBuilder.ApplyToExe(Const ExeFileSrc, ExeFileDest:string);
Var
  Header:THeader;
  hInput, hOutput : Longint;
  NumRead,NumWritten : LongInt;
  Buffer : Array[1..4096] of byte;
  AddrResourceFile,Verif : Int64;
  i:integer;
  TmpFile:string;
begin
  if FResources.Count=0 then
    Raise Exception.Create('No Resourcefile(s)');
  if not FileExists(ExeFileSrc) then
    Raise Exception.Create('File not found : '#13#10+ExeFileSrc);
  DeleteFile(ExeFileDest);
  if FileExists(ExeFileDest) then
    Raise Exception.Create('File busy or readonly '#13#10+ExeFileDest);
  for i:=0 to FResources.Count-1 do
    if Not FileExists(FResources[i].FileName) then
      Raise Exception.Create('File not found : '#13#10+FResources[i].FileName);
  TmpFile:= IncludeTrailingPathDelimiter(GetTempDir) +
    FormatDateTime('yyyymmddhhnnsszzz', Now) + '.tmp';

  CopyFile(ExeFileSrc,TmpFile);
  if not FileExists(TmpFile) then
    Raise Exception.Create('Apply error');

  hInput:=FileOpen(TmpFile,fmOpenRead);
  hOutput:=FileCreate(ExeFileDest);
  AddrResourceFile:=0;
  Repeat
    NumRead:=FileRead(hInput,Buffer,Sizeof(Buffer));
    NumWritten:=FileWrite(hOutput,Buffer,NumRead);
    inc(AddrResourceFile,NumWritten);
  Until (NumRead<=0) or (NumWritten<>NumRead);
  FileClose(hInput);
  DeleteFile(TmpFile);
  if NumRead=-1 then
  begin
    FileClose(hOutput);
    DeleteFile(ExeFileDest);
    Raise Exception.Create('File busy or readonly '#13#10+ExeFileSrc);
  end;
  for i:=0 to FResources.Count-1 do
  begin
    hInput:=FileOpen(FResources[i].FileName,fmOpenRead);
    Header.Size:=0;
    repeat
      NumRead:=FileRead(hInput,Buffer,Sizeof(Buffer));
      Header.Size:=Header.Size+NumRead;
    until (NumRead=0);
    Header.Last:=(i=FResources.Count-1);
    Header.Name:=FResources[i].Name;
    FileWrite(hOutput,Header,sizeOf(Header));

    FileSeek(hInput,0, fsFromBeginning);
    Repeat
      NumRead:=FileRead(hInput,Buffer,Sizeof(Buffer));
      NumWritten:=FileWrite(hOutput,Buffer,NumRead);
    Until (NumRead=0) or (NumWritten<>NumRead);
    FileClose(hInput);
  end;

  verif:=-AddrResourceFile;
  FileWrite(hOutput,Verif,sizeof(Verif));
  FileWrite(hOutput,AddrResourceFile,sizeof(AddrResourceFile));
  FileClose(hOutput);
end;

constructor TResourceExeReader.Create;
begin
  FExeFile:=ParamStr(0);
  FResources:=TStringList.Create;
end;

destructor TResourceExeReader.Destroy;
begin
  FResources.Free;
  inherited;
end;

procedure TResourceExeReader.SetExeFile(Value:string);
begin
  if Value<>FExeFile then
  begin
    FExeFile:=Value;
    FResources.Clear;
  end;
end;

procedure TResourceExeReader.List(AList:TStrings);
Var
  Header:THeader;
  hInput: longint;
  NumRead: longint;
  AddrResourceFile, Verif : Int64;
begin
  AList.Clear;
  if not FileExists(FExeFile) then
    Raise Exception.Create('File not found : '#13#10+ExeFile);

  hInput:=FileOpen(FExeFile,fmOpenRead);
  FileSeek(hInput,-SizeOf(AddrResourceFile), fsFromEnd);
  FileRead(hInput,AddrResourceFile,Sizeof(AddrResourceFile));
  FileSeek(hInput,-(SizeOf(AddrResourceFile)+SizeOf(Verif)), fsFromEnd);
  FileRead(hInput,Verif,Sizeof(Verif));
  if -Verif<>AddrResourceFile then
  begin
    FileClose(hInput);
    exit;
  end;
  Repeat
    FileSeek(hInput,AddrResourceFile,fsFromBeginning);
    NumRead:=FileRead(hInput,Header,SizeOf(Header));
    if NumRead>0 then
    begin
      AList.AddObject(Header.Name,TObject(PtrUint(AddrResourceFile)));
      inc(AddrResourceFile,Header.Size+NumRead);
    end;
  Until (NumRead=0) or Header.Last;
  FileClose(hInput);
end;

function TResourceExeReader.GetCount:integer;
begin
  if FResources.Count=0 then
    List(FResources);
  Result:=FResources.Count;
end;

function TResourceExeReader.ResourceExists(Const ResourceName:string):boolean;
begin
  if FResources.Count=0 then
    List(FResources);
  FResources.CaseSensitive:=False;
  Result:=FResources.IndexOf(ResourceName)>-1;
end;

procedure TResourceExeReader.SaveToDir(Const Dir:string);
var
  i:integer;
begin
  if not DirectoryExists(Dir) then
    Raise Exception.Create(Dir+' : Directory not exists');
  if FResources.Count=0 then
    List(FResources);
  if FResources.Count=0 then
    Raise Exception.Create('No File to save');
  for i:=0 to FResources.Count-1 do
    SaveToFile(FResources[i],Dir+FResources[i]);
end;

procedure TResourceExeReader.SaveToFile(Const ResourceFile:string);
begin
  SaveToFile(ExtractFileName(ResourceFile),ResourceFile);
end;

procedure TResourceExeReader.SaveToFile(Const ResourceName:string;Const ResourceFile:string);
Var
  Header:THeader;
  hInput, hOutput : Longint;
  NumRead,NumWritten,Total : LongInt;
  Buffer : Array[1..4096] of byte;
  ix:integer;
begin
  if FResources.Count=0 then
    List(FResources);
  FResources.CaseSensitive:=False;
  ix:=FResources.IndexOf(ResourceName);
  if ix=-1 then
    Raise Exception.Create('File not found : '+#13#10+ResourceName);
  DeleteFile(ResourceFile);
  if FileExists(ResourceFile) then
    Raise Exception.Create('File busy or readonly '#13#10+ResourceFile);

  hInput:=FileOpen(ExeFile,fmOpenRead);
  FileSeek(hInput,int64(FResources.Objects[ix]),fsFromBeginning);
  FileRead(hInput,Header,SizeOf(Header));
  if UpperCase(Header.Name)<>UpperCase(ResourceName) then
  begin
    FileClose(hInput);
    Raise Exception.Create('Catalog error : '+#13#10+ResourceName);
  end;
  hOutput:=FileCreate(ResourceFile);
  Total:=0;
  Repeat
    NumRead:=FileRead(hInput,Buffer,Sizeof(Buffer));
    if Total+NumRead>Header.Size then
      NumRead:=Header.Size-Total;
    NumWritten:=FileWrite(hOutput,Buffer,NumRead);
    inc(Total,NumWritten);
  Until (NumRead=0) or (NumWritten<>NumRead) or (Total>=Header.Size );
  FileClose(hInput);
  FileClose(hOutput);
end;

function TResourceExeReader.SaveToString(Const ResourceName:string):string;
var
  TmpFile:String;
  FFile:TStringList;

begin
  Result:='';
  TmpFile:= IncludeTrailingPathDelimiter(GetTempDir) +
            FormatDateTime('yyyymmddhhnnsszzz', Now) + '.tmp';
  FFile:=TStringList.Create;
  Try
    SaveToFile(ResourceName,TmpFile);
    FFile.LoadFromFile(TmpFile);
    Result:=FFile.Text;
  Finally
    FFile.Free;
    DeleteFile(TmpFile);
  end;
end;

procedure TResourceExeReader.SaveToString(Const ResourceName:string;var Content:string);
begin
  Content:=SaveToString(ResourceName);
end;

procedure TResourceExeReader.SaveToStream(Const ResourceName:string;S:TStream);
var
  MS:TMemoryStream;
  TmpFile:String;
begin
  TmpFile:= IncludeTrailingPathDelimiter(GetTempDir) +
            FormatDateTime('yyyymmddhhnnsszzz', Now) + '.tmp';
  MS:=TMemoryStream.Create;
  Try
    SaveToFile(ResourceName,TmpFile);
    MS.LoadFromFile(TmpFile);
    MS.Position:=0;
    S.Position:=0;
    MS.SaveToStream(S);
    S.Position:=0;
  Finally
    DeleteFile(TmpFile);
    MS.Free;
  end;
end;


end.


