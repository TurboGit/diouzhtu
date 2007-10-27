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

with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada.Exceptions;
with Ada.Directories;

with AWS.MIME;
with AWS.Messages;
with AWS.Parameters;
with AWS.Services.Directory;
with AWS.Services.Web_Block.Registry;

with Gwiad.Plugins.Services.Registry;
with Gwiad.Web.Virtual_Host;
with Wiki_Interface;

with Wiki_Website.Config;
with Wiki_Website.Lock;
with Wiki_Website.Service;
with Wiki_Website.Template_Defs.Top;
with Wiki_Website.Template_Defs.Edit;
with Wiki_Website.Template_Defs.Preview;

package body Wiki_Website.Callbacks is

   use Ada.Strings.Unbounded;
   use Ada.Exceptions;
   use Ada.Text_IO;
   use Ada;

   use Wiki_Website;
   use Wiki_Website.Config;
   use Wiki_Interface;

   ------------------
   -- CSS_Callback --
   ------------------

   function CSS_Callback (Request : in Status.Data) return Response.Data is
      Name     : constant Wiki_Name := Get_Wiki_Name (Request);
      URI      : constant String    := Status.URI (Request);
      File     : constant String    :=
                    Wiki_CSS_Root (Name) & "/"
                    & URI (URI'First + Wiki_Web_CSS'Length + 2 .. URI'Last);
   begin
      if Ada.Directories.Exists (File) then
         return Response.File (MIME.Content_Type (File), File);
      else
         return Response.Acknowledge (Status_Code  => Messages.S404);
      end if;
   exception
      when E : others => Ada.Text_IO.Put_Line
           (Ada.Exceptions.Exception_Information (E));
         return Response.Acknowledge (Status_Code  => Messages.S404);
   end CSS_Callback;

   ----------------------
   -- Default_Callback --
   ----------------------

   function Default_Callback (Request : in Status.Data) return Response.Data is
      use type Messages.Status_Code;
   begin
      Default_Callback_Body :
      declare
         URI          : constant String := Status.URI (Request);
         Translations : Templates.Translate_Set;
         Web_Page     : Response.Data;
      begin

         Web_Page := AWS.Services.Web_Block.Registry.Build
           (Key           => Gwiad.Web.Virtual_Host.Get_Hostname
              (AWS.Status.Host (Request)) & URI,
            Request       => Request,
            Translations  => Translations,
            Cache_Control => Messages.Prevent_Cache);

         if Response.Status_Code (Web_Page) = Messages.S404 then
            --  Page not found
            return Response.Build
              (Content_Type  => MIME.Text_HTML,
               Message_Body  => "<p>Page not found !</p>");
         else
            return Web_Page;
         end if;
      end Default_Callback_Body;
   exception
      when E : others => Ada.Text_IO.Put_Line
           ("(Default_Callback) : Failed ! "
            & Exception_Information (E));
         return Response.Acknowledge
           (Status_Code  => Messages.S500,
            Message_Body => "<p>Internal error</p>",
            Content_Type => MIME.Text_HTML);
   end Default_Callback;

   ---------------
   -- Edit_Page --
   ---------------

   procedure Edit_Page
     (Request      : in     Status.Data;
      Context      : access AWS.Services.Web_Block.Context.Object;
      Translations : in out Templates.Translate_Set)
   is
      use AWS.Status;
      use Ada.Directories;
      pragma Unreferenced (Context);

      Name        : constant Wiki_Name := Get_Wiki_Name (Request);
      Get_URI     : constant String := URI (Request);
      Simple_Name : constant String := Get_Filename (Get_URI);
      Filename    : constant String :=
                      Wiki_Text_Dir (Name) & "/" & Simple_Name;

      Text_Plain : Unbounded_String;
      Text_File  : File_Type;

      Wait_Lock  : Duration;

   begin

      Templates.Insert
        (Translations,
         Templates.Assoc (Template_Defs.Top.WIKI_NAME, String (Name)));

      if not Gwiad.Plugins.Services.Registry.Exists (Wiki_Service_Name) then
         Templates.Insert
           (Translations,
            Templates.Assoc
              (Template_Defs.Edit.ERROR, "<p>Service down</p>"));
         return;
      end if;

      if Exists (Filename) then
         if Kind (Filename) /= Ordinary_File then
            if Kind (Filename) = Directory then
               Templates.Insert
                 (Translations,
                  Templates.To_Set (AWS.Services.Directory.Browse
                    (Directory_Name => Filename,
                     Request        => Request)));
            end if;
            return;
         end if;

         --  Claim lock

         Lock.Manager.Claim (Filename     => Filename,
                             User         => "wikiauthor",
                             Time_To_Wait => Wait_Lock);

         if Wait_Lock > 0.0
           or else not VCS_Engine.Lock (Filename => Filename)
         then
            Templates.Insert
              (Translations,
               Templates.Assoc
                 (Template_Defs.Edit.ERROR,
                  "<p>File is currently locked</p>"));
            return;
         end if;

         Open (File => Text_File,
               Mode => In_File,
               Name => Filename);

         while not End_Of_File (File => Text_File) loop
            Append (Text_Plain, Get_Line (Text_File));
            Append (Text_Plain, ASCII.LF);
         end loop;

         Close (File => Text_File);
      end if;

      Templates.Insert
        (Translations,
         Templates.Assoc (Template_Defs.Edit.TEXT_PLAIN, Text_Plain));
      Templates.Insert
        (Translations,
         Templates.Assoc (Template_Defs.Edit.FILENAME, Simple_Name));
   end Edit_Page;

   --------------------
   -- Image_Callback --
   --------------------

   function Image_Callback (Request : in Status.Data) return Response.Data is
      URI  : constant String := Status.URI (Request);
      Name : constant Wiki_Name := Get_Wiki_Name (Request);
      File : constant String := Wiki_Data_Root (Name)
        & "/" & Wiki_Image_Dir (Name) & "/"
        & URI (URI'First + Wiki_Web_Image'Length + 2 .. URI'Last);
   begin
      if Ada.Directories.Exists (File) then
         return Response.File (MIME.Content_Type (File), File);
      else
         return Response.Acknowledge (Status_Code => Messages.S404);
      end if;
   exception
      when E : others => Ada.Text_IO.Put_Line
           (Ada.Exceptions.Exception_Information (E));
         return Response.Acknowledge (Status_Code  => Messages.S404);
   end Image_Callback;

   -----------------
   -- JS_Callback --
   -----------------

   function JS_Callback (Request : in Status.Data) return Response.Data is
      URI : constant String := Status.URI (Request);
      Name : constant Wiki_Name := Get_Wiki_Name (Request);
      File : constant String := Wiki_JS_Root (Name) & "/"
        & URI (URI'First + Wiki_Web_JS'Length + 2 .. URI'Last);
   begin
      if Ada.Directories.Exists (File) then
         return Response.File (MIME.Content_Type (File), File);
      else
         return Response.Acknowledge (Status_Code => Messages.S404);
      end if;
   exception
      when E : others => Ada.Text_IO.Put_Line
        (Ada.Exceptions.Exception_Information (E));
      return Response.Acknowledge (Status_Code  => Messages.S404);
   end JS_Callback;

   ------------------
   -- Preview_Page --
   ------------------

   procedure Preview_Page
     (Request      : in     Status.Data;
      Context      : access AWS.Services.Web_Block.Context.Object;
      Translations : in out Templates.Translate_Set)
   is
      use Ada.Directories;
      pragma Unreferenced (Context);
      P             : constant Parameters.List := Status.Parameters (Request);
      Save          : constant String          :=
                        Parameters.Get (P, Template_Defs.Preview.HTTP.save);
      Text_Plain    : constant String          :=
                        Parameters.Get (P,
                                        Template_Defs.Preview.HTTP.text_plain);
      Get_URI       : constant String := Status.URI (Request);
      Name          : constant Wiki_Name := Get_Wiki_Name (Request);
      Wiki_Filename : constant String := Get_Filename (Get_URI);
      Filename      : constant String :=
                        Wiki_Text_Dir (Name) & "/" & Wiki_Filename;

   begin

      Templates.Insert
        (Translations,
         Templates.Assoc (Template_Defs.Top.WIKI_NAME, String (Name)));

      if not Gwiad.Plugins.Services.Registry.Exists (Wiki_Service_Name) then
         Templates.Insert
           (Translations,
            Templates.Assoc
              (Template_Defs.Preview.ERROR, "<p>Service down</p>"));
         return;
      end if;

      --  Check Lock

      if Exists (Filename)
        and not Lock.Manager.Check (Filename, "wikiauthor")
      then
         Templates.Insert
           (Translations,
            Templates.Assoc
              (Template_Defs.Preview.ERROR, "<p>Your lock has expired</p>"));
         return;
      end if;

      if Save /= "" then
         Save_Preview :
         declare
            Text_File   : File_Type;
            Initial_Rev : Boolean := False;
            Lock_Delay  : Duration;
         begin

            if Exists (Filename) and then
              Kind (Filename) = Ordinary_File then

               Delete_File (Filename);
            else
               Create_Path (Containing_Directory (Filename));
               Initial_Rev := True;
            end if;

            if Text_Plain /= "" then
               --  Do not create empty file

               Create (File => Text_File,
                       Mode => Out_File,
                       Name => Filename);

               Put (File => Text_File,
                    Item => Text_Plain);

               Close (File => Text_File);

               if Initial_Rev then

                  --  Lock the file before adding it

                  Wiki_Website.Lock.Manager.Claim
                    (Filename     => Filename,
                     User         => "wikiauthor",
                     Time_To_Wait => Lock_Delay);

                  if Lock_Delay = 0.0
                    and then not VCS_Engine.Add (Filename => Filename,
                                                 Author   => "wikiauthor")
                  then
                     Templates.Insert
                       (Translations,
                        Templates.Assoc
                          (Template_Defs.Edit.ERROR,
                           "<p>Add Failed !</p>"));

                     --  Unlock the file

                     Wiki_Website.Lock.Manager.Release
                       (Filename     => Filename,
                        User         => "wikiauthor");

                     return;
                  end if;
               else
                  if not VCS_Engine.Commit (Filename => Filename,
                                            Message  => "wiki commit",
                                            Author   => "wikiauthor") then
                     Templates.Insert
                       (Translations,
                        Templates.Assoc
                          (Template_Defs.Edit.ERROR,
                           "<p>Commit Failed !</p>"));
                     return;
                  end if;

                  if Ada.Directories.Exists
                    (Wiki_HTML_Dir (Name) & "/" & Wiki_Filename) then
                     Ada.Directories.Delete_File
                       (Wiki_HTML_Dir (Name) & "/" & Wiki_Filename);
                  end if;
               end if;

               Templates.Insert
                 (Translations,
                  Templates.Assoc (Template_Defs.Preview.HAS_BEEN_SAVED,
                    Wiki_Filename));

               --  Release the file lock

               Wiki_Website.Lock.Manager.Release
                 (Filename     => Filename,
                  User         => "wikiauthor");

            end if;
         end Save_Preview;
      else
         Generate_Preview :
         declare
            Get_Service : constant GW_Service'Class := Service.Get (Name);
         begin
            Templates.Insert
              (Translations,
               Templates.Assoc
                 (Template_Defs.Preview.PREVIEW,
                  HTML_Preview (Get_Service, Text_Plain)));
         end Generate_Preview;

         Templates.Insert
           (Translations,
            Templates.Assoc (Template_Defs.Preview.TEXT_PLAIN, Text_Plain));
         Templates.Insert
           (Translations,
            Templates.Assoc
              (Template_Defs.Preview.FILENAME, Wiki_Filename));
      end if;
   end Preview_Page;

end Wiki_Website.Callbacks;
