------------------------------------------------------------------------------
--                               Diouzhtu                                   --
--                                                                          --
--                           Copyright (C) 2007                             --
--                            Olivier Ramonat                               --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.       --
------------------------------------------------------------------------------

with Diouzhtu.Attribute;
with GNAT.Regpat;

package body Diouzhtu.Code is

   use GNAT.Regpat;

   function End_Code (Block : String) return String;
   --  Search for a "end code." to close a block code

   --------------
   -- End_Code --
   --------------

   function End_Code (Block : String) return String is
      Extract  : constant Pattern_Matcher :=
        Compile (".*?(end code.)", Case_Insensitive + Single_Line);
      Matches : Match_Array (0 .. 1);
      Result  : Unbounded_String := Null_Unbounded_String;
   begin
      Match (Extract, Block, Matches);
      if Matches (0) = No_Match then
         return "";
      end if;

      if Block'First < Matches (1).First - 1 then
         if Block (Matches (1).First - 1) = ASCII.Lf then
            --  Skip the last Lf when end code. at the end of a block
            Append (Result, Block (Block'First .. Matches (1).First - 2));
         else
            Append (Result, Block (Block'First .. Matches (1).First - 1));
         end if;
      else
         --  This is a new block. Adds the missing blank line
         Append (Result, ASCII.Lf & ASCII.Lf);
      end if;

      return To_String (Result) & "</code></pre></p>" & ASCII.Lf;
   end End_Code;

   -----------
   -- Parse --
   -----------

   procedure Parse
     (Wiki          : in Wiki_Information;
      Block         : in String;
      Is_Code_Block : in out Boolean;
      Result        : out Unbounded_String)
   is
      procedure Begin_Code;
      --  Search for a begin code block tag "code." else call Diouzhtu.Parse

      procedure Begin_Code is
         Extract  : constant Pattern_Matcher :=
                      Compile ("^code(_[a-zA-Z]+?)??" &
                               Attribute.Get_Pattern & "\.\s(.*?)$",
                               Case_Insensitive + Single_Line);
         Count    : constant Match_Count := Paren_Count (Extract);
         Matches  : Match_Array (0 .. Count);
      begin
         Match (Extract, Block, Matches);
         if Matches (0) = No_Match then
            Append (Result, Diouzhtu.Parse (Wiki, Block_Level, Block));
            return;
         end if;

         --  This is a code block

         Is_Code_Block := True;

         Result := To_Unbounded_String ("<p><pre><code");

         if Matches (2) /= No_Match then
            Append (Result, Attribute.Extract
                      (Block (Matches (2).First .. Matches (2).Last),
                       Block (Matches (1).First + 1 .. Matches (1).Last)));
         elsif Matches (1) /= No_Match then
            Append (Result, " class='" &
                      Block (Matches (1).First + 1 .. Matches (1).Last) &
                      "'");
         end if;

         Append (Result, ">");

         if Matches (Count) /= No_Match
           and then Matches (Count).First < Block'Last then
            declare
               End_Code_Block : constant String :=
                 End_Code (Block (Matches (Count).First .. Block'Last));
            begin
               if End_Code_Block /= "" then
                  Is_Code_Block := False;
                  Append (Result, End_Code_Block);
               else
                  Append (Result, Block (Matches (Count).First .. Block'Last));
               end if;
            end;
         end if;
      end Begin_Code;

   begin

      if not Is_Code_Block then
         Begin_Code;
      else
         declare
            End_Code_Block : constant String := End_Code (Block);
         begin
            if End_Code_Block /= "" then
               Is_Code_Block := False;
               Append (Result, End_Code_Block);
            else
               Append (Result, ASCII.Lf & ASCII.Lf & Block);
            end if;
         end;
      end if;
   end Parse;

end Diouzhtu.Code;