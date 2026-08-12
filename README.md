# Proiect_3-FPGA
Senzor de Temperatură prin I2C

Acest proiect continuă direct proiectul UART realizat anterior.
Implementați un master I2C în SystemVerilog, fără IP core-uri Xilinx. Master-ul trebuie să comunice cu senzorul de temperatură de pe placă, să citească periodic valoarea temperaturii și să o convertească în grade Celsius conform specificațiilor din datasheet-ul senzorului. 

I2C este un protocol de comunicație serială sincronă utilizat pentru conectarea mai multor periferice folosind doar două linii de comunicație:
- SCL (Serial Clock Line) – linia de ceas, controlată de master și utilizată pentru sincronizarea transferului de date
- SDA (Serial Data Line) – linia bidirecțională prin care sunt transmise adresele, comenzile și datele
  
În cadrul comunicației, master-ul controlează întreaga secvență de transfer. O tranzacție I2C este alcătuită din următoarele etape:
1. Generarea condiției START.
2. Transmiterea adresei dispozitivului slave (7 biți) și a bitului R/W, care indică operația de citire sau scriere.
3. Recepționarea semnalului ACK/NACK din partea dispozitivului slave.
4. Transferul unuia sau mai multor octeți de date.
5. Generarea condiției STOP, prin care magistrala este eliberată.
În cazul operațiilor de citire, master-ul primește datele de la dispozitivul slave și transmite un semnal ACK sau NACK după fiecare octet recepționat.

# Pașii de implementare  
Primul pas constă în definirea interfeței modulului i2c_master, care va reprezenta componenta principală responsabilă de comunicarea pe magistrala I2C. Modulul va primi semnale de control (reset, comandă de citire/scriere, adresa dispozitivului slave și datele care trebuie transmise) și va controla liniile SDA și SCL.   
În această etapă vor fi definite și registrele interne necesare, precum registrul de deplasare (shift_register), contorul de biți (bit_counter) și registrele utilizate pentru memorarea adresei dispozitivului și a datelor transferate.   
În protocolul I2C, semnalul de ceas este generat exclusiv de dispozitivul master. Deoarece placa Nexys A7 utilizează un ceas de 100 MHz, va fi implementat un modul separat care va împărți această frecvență pentru a genera semnalul SCL la frecvența dorită.   
Generarea semnalului SCL: Placa Nexys A7 folosește un ceas de 100 MHz. Se implementează un divider care generează un semnal intern de 4 × frecvența I2C.   
Fiecare bit de pe magistrală este împărțit în 4 faze:   
phase = 0 → SCL high   
phase = 1 → front descrescător   
phase = 2 → SCL low   
phase = 3 → front crescător     
Pe faza low se pune bitul pe SDA, iar pe faza high se eșantionează valoarea de pe SDA.   
Linia SDA este utilizată atât pentru transmiterea, cât și pentru recepția datelor. În timpul operațiilor de scriere, master-ul transmite pe această linie adresa dispozitivului și datele propriu-zise, iar în timpul operațiilor de citire monitorizează nivelul logic prezent pe magistrală pentru a recepționa datele și semnalele ACK/NACK.   
Funcționarea master-ului I2C va fi controlată printr-o mașină de stări finite, fiecare stare corespunzând unei etape din protocolul I2C.   
FSM-ul va include următoarele stări:
* IDLE – magistrala este liberă și se așteaptă semnalul enable
* START – se generează condiția START (SDA trece din 1 în 0 cât timp SCL este 1)
* ADDR – se transmite, bit cu bit, adresa slave-ului + bitul R/W
* ACK_ADDR – se eliberează SDA și se citește ACK-ul de la slave
* WRITE_DATA – se transmite un octet de date bit cu bit
* ACK_WRITE – se erifică ACK-ul după scrierea unui octet
* RESTART – se generează Repeated START (util pentru scriere pointer + citire)
* READ_DATA - se recepționează un octet de la slave bit cu bit
* ACK_READ - masterul trimite ACK pentru a cere următorul octet
* NACK - masterul trimite NACK pentru a semnala că a citit ultimul octet
* STOP - se generează condiția STOP (SDA trece din 0 în 1 cât timp SCL este 1)
* DONE_ST - tranzacția s-a terminat; se activează done și se revine în IDLE

Transmiterea fiecărui bit va fi sincronizată cu semnalul SCL, iar trecerea între stări se va realiza numai după finalizarea operației corespunzătoare fiecărei etape.  
După implementarea FSM-ului, vor fi dezvoltate secvențele complete de comunicație pentru operațiile de scriere și citire.   
Secvențe de comunicație   
Operație de scriere:   
IDLE → START → ADDR → ACK_ADDR → WRITE_DATA → ACK_WRITE → … → STOP → DONE_ST   
Operație de citire:   
IDLE → START → ADDR → ACK_ADDR → READ_DATA → ACK_READ / NACK → … → STOP → DONE_ST   
La citire, după fiecare octet (cu excepția ultimului) masterul trimite ACK. După ultimul octet trimite NACK și apoi generează STOP.
