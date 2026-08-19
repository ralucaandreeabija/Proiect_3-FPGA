# Proiect_3-FPGA
Senzor de Temperatură prin I2C
Acest proiect continuă direct proiectul UART realizat anterior.
Implementați un master I2C în SystemVerilog, fără IP core-uri Xilinx. Master-ul trebuie să comunice cu senzorul de temperatură de pe placă (ADT7420), să citească periodic valoarea temperaturii și să o convertească în grade Celsius conform specificațiilor din datasheet-ul senzorului.
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
Primul pas constă în definirea interfeței modulului i2c_master, care reprezintă componenta principală responsabilă de comunicarea pe magistrala I2C. Modulul primește semnale de control (reset, enable, addr, reg_addr, data_in, rw) și controlează liniile SDA și SCL în regim open-drain. În plus, oferă semnale de status (busy, done, ack_error) și un semnal de debug (ack_debug) care indică în ce etapă a eșuat un ACK.
În această etapă au fost definite și registrele interne necesare:
- shift_reg – registru de deplasare pentru transmiterea biților
- read_shift – registru pentru recepționarea unui octet
- register_reg – memorează adresa registrului care trebuie citit
- write_data_reg – date pentru eventuală scriere
- rdata – buffer pe 16 biți pentru cei doi octeți citiți (MSB + LSB)
- bit_counter – indexul bitului curent (de la 7 la 0)
- read_second_byte – flag care diferențiază citirea primului octet (MSB) de al doilea (LSB)
- phase – contor pe 2 biți care împarte fiecare bit / condiție în 4 faze

Generarea semnalului SCL
Placa Nexys A7 folosește un ceas de 100 MHz. Se implementează un divider intern care generează un semnal i2c_tick la frecvența 4 × I2C_FREQ (implicit 400 kHz pentru I2C la 100 kHz).
Fiecare bit de pe magistrală este împărțit în 4 faze:
- phase = 0 → SCL LOW / pregătire
- phase = 1 → SDA este stabilit (bitul este pus pe linie)
- phase = 2 → SCL HIGH → aici se citește SDA (eșantionare)
- phase = 3 → terminarea bitului și trecerea la următorul

Pe faza LOW se pregătește bitul pe SDA, iar pe faza HIGH se eșantionează valoarea de pe SDA (atât pentru ACK-uri, cât și pentru datele citite). 
Linia SDA este utilizată atât pentru transmiterea, cât și pentru recepția datelor. În timpul operațiilor de scriere, master-ul transmite pe această linie adresa 
dispozitivului și adresa registrului, iar în timpul operațiilor de citire eliberează linia (open-drain) și monitorizează nivelul logic prezent pe magistrală pentru a 
recepționa datele și semnalele ACK/NACK.

Funcționarea master-ului I2C este controlată printr-o mașină de stări finite, fiecare stare corespunzând unei etape din protocolul I2C. FSM-ul include următoarele stări: 
ST_IDLE – magistrala este liberă și se așteaptă semnalul enable 
ST_START – se generează condiția START (SDA trece din 1 în 0 cât timp SCL este 1) 
ST_ADDR_WRITE – se transmite, bit cu bit, adresa slave-ului + bitul Write (0) 
ST_ACK_ADDR_WRITE – se eliberează SDA și se citește ACK-ul de la slave 
ST_REGISTER – se transmite adresa registrului (pointer) bit cu bit 
ST_ACK_REGISTER – se citește ACK-ul după scrierea pointer-ului 
ST_RESTART – se generează Repeated START (util pentru secvența scriere pointer + citire) 
ST_ADDR_READ – se transmite adresa slave-ului + bitul Read (1) 
ST_ACK_ADDR_READ – se citește ACK-ul după adresa de citire 
ST_READ_BYTE – se recepționează un octet de la slave bit cu bit 
ST_MASTER_ACK – master-ul trimite ACK după primul octet (MSB) pentru a cere următorul 
ST_MASTER_NACK – master-ul trimite NACK după al doilea octet (LSB) pentru a semnala sfârșitul citirii 
ST_STOP – se generează condiția STOP (SDA trece din 0 în 1 cât timp SCL este 1) 
ST_DONE – tranzacția s-a terminat; se activează done (puls), se actualizează data_out și se revine în IDLE
  
Transmiterea și recepția fiecărui bit sunt sincronizate cu i2c_tick și cu cele 4 faze, iar trecerea între stări se realizează numai după finalizarea operației corespunzătoare fiecărei etape. 
Secvențe de comunicație 
Operație de citire (rw = 1) – secvența folosită pe placă: 
IDLE → START → ADDR_WRITE → ACK_ADDR_WRITE → REGISTER → ACK_REGISTER → RESTART → ADDR_READ → ACK_ADDR_READ → READ_BYTE (MSB) → MASTER_ACK → READ_BYTE (LSB) → MASTER_NACK → STOP → DONE → IDLE 
Operație de scriere (rw = 0): 
IDLE → START → ADDR_WRITE → ACK_ADDR_WRITE → REGISTER → ACK_REGISTER → STOP → DONE → IDLE
 
La citire, după primul octet (MSB) master-ul trimite ACK. După al doilea octet (LSB) trimite NACK și apoi generează STOP.
Semnalul ack_debug permite identificarea precisă a etapei în care a eșuat un ACK:
00 – niciun ACK eșuat
01 – ACK după adresa WRITE
10 – ACK după registru
11 – ACK după adresa READ

# Integrare pe placă (temp_top) și testare
Pentru testarea pe placa Nexys A7 a fost realizat modulul de nivel superior temp_top, care integrează:

Power-on reset – un contor scurt care menține sistemul în reset la pornire, combinat cu butonul de reset. 
Master I2C – instanțiat cu adresa slave ADT7420 (7'h4B) și registrul de temperatură (8'h00). Operația este forțată pe citire (rw = 1). 
FSM de citire periodică – citește temperatura la aproximativ 0,5 s (contor de 50 000 000 cicluri la 100 MHz). Include mecanism de timeout (500 000 cicluri) atât la 
pornirea tranzacției, cât și la așteptarea semnalului done, pentru a preveni blocarea în caz de eroare pe magistrală. 
Conversie temperatură – modulul temp_convert transformă valoarea brută pe 16 biți (format 13 biți semnat + fracție) în temperatură × 10 (temp_x10), conform datasheet-ului 
ADT7420. 
Generare string ASCII – se formează un șir de 5 caractere de tipul „25.3 ” care este trimis prin UART către logger-ul existent din proiectul anterior. (încă nu am 
implementat utilizarea logger-ului) 
Afișaj 7-segmente – temperatura este afișată în format „XX.X C” pe cele 4 digite din stânga, folosind modulele temp_to_7seg și display_controller. 
LED-uri de debug – oferă feedback vizual în timp real: 
LED0 = i2c_busy 
LED1 = i2c_done 
LED2 = i2c_ack_error 
LED3 = i2c_enable 
LED4 / LED5 = starea FSM-ului de citire periodică 
LED6 / LED7 = starea liniilor SDA / SCL 
LED15–8 = octetul superior al temperaturii brute

# Observații din testarea pe placă

Secvența cu Repeated START (scriere pointer + citire) s-a dovedit stabilă și este cea recomandată de datasheet-ul ADT7420. 
Fără mecanism de timeout, în cazul unui ACK lipsă master-ul putea rămâne blocat în starea de așteptare; adăugarea timeout-ului a rezolvat problema. 
Semnalul ack_debug a fost esențial pentru depanare: a permis identificarea rapidă a etapei în care slave-ul nu răspundea (în special la adresa de citire). 
Divider-ul pe 4 faze oferă o margine de timp confortabilă pentru setup/hold pe magistrală la 100 kHz. 
Afișajul 7-segmente și LED-urile au confirmat că valoarea citită corespunde temperaturii reale din încăpere, iar conversia în grade Celsius este corectă.
 
Au fost adăugate stări dedicate (ST_REGISTER, ST_RESTART, ST_MASTER_ACK, ST_MASTER_NACK) pentru a face fluxul mai clar și mai ușor de depanat. 
S-a introdus semnalul ack_debug pe 2 biți. 
La nivel de sistem (temp_top) s-a adăugat citirea periodică cu timeout, conversia temperaturii, generarea string-ului ASCII pentru UART și maparea pe afișajul 7-segmente + 
LED-uri de debug.
