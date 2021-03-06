unit FindUnit.StringPositionList;

interface

uses
	FindUnit.Header, Generics.Collections, Classes;

type
  TStringPositionList = class(TList<TStringPosition>)
  private
    FDuplicates: TDuplicates;

    function IsDuplicated(Item: TStringPosition): Boolean;
  public
    function Add(const Value: TStringPosition): Integer;

    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
  end;

implementation

uses
	SysUtils;

{ TStringPositionList }

function TStringPositionList.Add(const Value: TStringPosition): Integer;
begin
  case Duplicates of
    dupIgnore:
    begin
      if not IsDuplicated(Value) then
        inherited Add(Value);
    end;
    dupAccept: inherited Add(Value);
    dupError:
    begin
      if IsDuplicated(Value) then
        raise Exception.Create('Duplicated item');
      inherited Add(Value);
    end;
  end;
end;

function TStringPositionList.IsDuplicated(Item: TStringPosition): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Count -1 do
    if Item.Value = Items[i].Value then
    begin
      Result := True;
      Exit;
    end;
end;

end.
