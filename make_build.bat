set "game_data_name=the_farmers_data"
set "archive_name=the_farmers.zip"

del /s /q build\*
rmdir /s /q build\
mkdir "build\%game_data_name%\"
mkdir "build\%game_data_name%\sounds"
del /s /q %archive_name%

robocopy sounds "build\%game_data_name%\sounds" /E
robocopy .\ "build" assets_used.txt
robocopy .\ "build\%game_data_name%" tiles.das
robocopy .\ "build\%game_data_name%" tiles.png
robocopy .\ "build\%game_data_name%" main.das
robocopy .\ "build" run.bat
robocopy .\..\..\ "build" dasbox.exe

"C:\Program Files\7-Zip\7z" a -tzip %archive_name% .\build\*

del /s /q build\*
rmdir /s /q build\