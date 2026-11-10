@echo off
rem Registra no Agendador de Tarefas do Windows a atualizacao automatica do painel:
rem todo dia, de hora em hora entre 08:00 e 20:00 (so com o PC ligado).
rem Para remover: schtasks /delete /tn "SIC Acompanhamento - atualizar" /f
schtasks /create /f /tn "SIC Acompanhamento - atualizar" /sc daily /st 08:00 /ri 60 /du 12:00 /tr "\"C:\Program Files\Git\bin\bash.exe\" -lc \"~/sic-acompanhamento/scripts/atualizar.sh --push >> ~/sic-acompanhamento/scripts/atualizar.log 2>&1\""
