# DE1-SoC

## Kako dodati nove I/O signale (tasteri, LED diode, 7-segmentni displej, itd.)

Potrebno je da promenite **dva fajla**. 

### Korak 1 — Dodajte port u modul najvišeg nivoa

**Fajl za promeniti:** `rtl/jtag_uart_top.v`

Modul najvišeg nivoa `jtag_uart_top` je mesto gde se deklarišu svi fizički pinovi na FPGA čipu. Trenutno ima samo dva porta:

```verilog
module jtag_uart_top (
    input wire CLOCK_50,
    input wire RSTN
);
```

Da biste dodali nove I/O, proširite listu portova. Na primer, da dodate 10 prekidača, 4 tastera, 10 crvenih LED dioda i šest 7-segmentnih displeja sa DE1-SoC ploče:

```verilog
module jtag_uart_top (
    input  wire        CLOCK_50,
    input  wire        RSTN,

    // Novi I/O
    input  wire [9:0]  SW,          // 10 kliznih prekidača
    input  wire [3:0]  KEY,         // 4 tastera (aktivno nisko)
    output wire [9:0]  LEDR,        // 10 crvenih LED dioda
    output wire [6:0]  HEX0,        // 7-segmentna cifra 0
    output wire [6:0]  HEX1,        // 7-segmentna cifra 1
    output wire [6:0]  HEX2,        // 7-segmentna cifra 2
    output wire [6:0]  HEX3,        // 7-segmentna cifra 3
    output wire [6:0]  HEX4,        // 7-segmentna cifra 4
    output wire [6:0]  HEX5         // 7-segmentna cifra 5
);
```

Takodje, top level signale koje ste dodali je potrebno povezati na vas *pfe* modul :)

### Korak 2 — Dodajte dodelu lokacija pinova (ograničenja)

**Fajl za promeniti:** `setup_project.tcl`

Ovo je **jedini fajl** koji sadrži mapiranja pinova na FPGA padove. Trenutno dodeljuje samo takt i reset:

```tcl
# --- CLOCK_50 ---
set_location_assignment PIN_AF14 -to CLOCK_50
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to CLOCK_50

# --- RESET_N ---
set_location_assignment PIN_AA14 -to RSTN
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to RSTN
```

Za svaki novi port koji ste dodali u Koraku 1, potreban vam je odgovarajući blok sa `set_location_assignment` i `set_instance_assignment` ovde. Imena pinova se nalaze u DE1-SoC korisničkom priručniku. Na primer:

```tcl
# --- Klizni prekidači ---
set_location_assignment PIN_AB12 -to SW[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[0]
set_location_assignment PIN_AC12 -to SW[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW[1]
# ... SW[2] do SW[9] ...

# --- Tasteri ---
set_location_assignment PIN_AA14 -to KEY[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to KEY[0]
# ... KEY[1] do KEY[3] ...

# --- Crvene LED diode ---
set_location_assignment PIN_V16  -to LEDR[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LEDR[0]
# ... LEDR[1] do LEDR[9] ...

# --- 7-segmentni displej HEX0 ---
set_location_assignment PIN_AE26 -to HEX0[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to HEX0[0]
# ... HEX0[1] do HEX0[6], zatim HEX1–HEX5 ...
```

#### Lokacije pinova
Mozete pogledati zvanicnu dokumentaciju **DE1-SoC_User_Manual.pdf** ili **pin_assignment_DE1_SoC.tcl**.

### Korak 3
```bash
make q_build
make q_program_only
```

### Korak 4
Profit?

<img src="images/rtl.png" alt="description" width="300">
