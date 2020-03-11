	.data	
		.align 2
bufor:		.space 2 # ustawiony tutaj dla łatwiejszego wczytywania danych z nagłówka
naglowek:	.space 54 # Nagłówek pliku BMP zawiera 54 bajty 

		.align 2
obrazek:	.asciiz "don.bmp"
		.align 2
output:		.asciiz "output.bmp"
		.align 2
blad_otw:	.asciiz "Błąd otwarcia pliku"

maska_filtru:	.byte	1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1, 24,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1 #1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1	
		.eqv	rozmiar_maski 	0x5
		.eqv	dzielnik	25

# s0 - deskryptor pliku
# s1 - liczba wierszy obrazka * liczba B na linie
# s2 - adres pierwszego bajtu zaalokowanej pamięci
# s5 - padding
	
	.text
main:	
	#wczytywanie_pliku:	
	li $v0, 13	# otwieranie pliku, $a0 = address of null-terminated string containing filename, $a1 = flags, $a2 = mode
	la $a0, obrazek	
	li $a1, 0
	li $a2, 0	 
	syscall		# v0 contains file descriptor (negative if error).
	
	bltz $v0, blad_otwarcia
	
	move $s0, $v0	# skopiowanie deskryptora pliku do rejestru s0
	
	#zapisz nagłówek pliku do bufora header
	li $v0, 14	# read from file, $a0 = file descriptor $a1 = address of input buffer, $a2 = max num of chars to read
	move $a0, $s0
	la $a1, naglowek	
	li $a2, 54	
	syscall # v0 contains number of characters read (0 if end-of-file, negative if error)
		
	lw $s6, naglowek+18 # szerokość obrazka
	
	#padding
	andi $t0, $s6, 3  # szerokość % 4	
	beqz $t0, zerowy_padding
	li $t1, 4
	subu $s5, $t1, $t0 # niezerowy padding
	
zerowy_padding:
	move $s5, $zero
	
	mul $s7, $s6, 3 # szerokość obrazka w bajtach
	addu $s7, $s7, $s5 # szerokość plus padding

	lw $s4, naglowek + 22 # wysokość obrazka
	lw $s1, naglowek + 34 # rozmiar obrazka w pikselach

	li $v0, 9	# sbrk
	move $a0, $s1	# liczba bajtów do zaalokowania
	syscall
	move $s2, $v0	# v0 zawiera adres zaalokowanej pamięci
	
	#przepisanie pikseli do zaalokowanej pamięci   
	li $v0, 14	# czytaj z pliku
	move $a0, $s0	# deskryptor pliku
	move $a1, $s2	# $a1 = address of input buffer
	move $a2, $s1	# przepisz tam $s1 pikseli, $a2 = maximum number of characters to read
	syscall	
	
	li $v0, 16	# zamknięcie pliku: 
	move $a0, $s0	# $a0 = file descriptor
	syscall
	
	#ładuje bufor do $s3
	li $v0, 9	# syscall 9, allocate heap memory
	move $a0, $s1	# data section size
	syscall
	move $s3, $v0	# $s3 zawiera adres zaalokowanej pamięci

# s1 - rozmiar obrazka
# s2 - początek tablicy pikseli
# s3 - tu zapiszemy nowy plik

# s6 - szerokość w pikselach
# s7 - szerokosc w bajtach (s6*3) plus padding
# s4 - wysokość obrazka

# t0 - wskaznik na pierwszy przetwarzany piksel obrazka
# t1 - wskaznik na piksel odpowiadający pierwszemu (lewy górny róg) okienku maski filtru dla bieżącego piksela
# t2 - szerokosc obrazka w pikselach (s6) - pomniejszona o 4 brzegowe piksele, dla których nie stosujemy filtru

# t3 - bieżący wiersz maski filtru
# t4 - bieżaca kolumna maski filtru
# t5 - wskażnik na miejsce w buforze, gdzie wpisujemy nową wartość RGB aktualnie przetwarzanego piksela
# t6, t7, t8 - BGR
# a0 - numer aktualnego okienka maski filtru (od 1 do 25)
# a2 - wiersz obrazka
# a3 - kolumna obrazka
		
	add $t0, $s2, $s7 # przesuwamy wskaźnik o dwa wiersze i dwa piksele (6 bajtów) dalej i cofamy go. 
	add $t0, $t0, $s7
	addi $t0, $t0, 6 # t0 - wskaznik na piksel poprzedzający pierwszy przetwarzany piksel obrazka. Poprzedzający - bo w pętli po
			 # kolumnach obrazka przeskoczymy o 1 piksel do przodu.
	addi $t0, $t0, -15 #bo niżej w petlach dodamy na początku 12 i 3
				
	subi $t2, $s6, 4 # liczba kolumn w wierszu pomniejszona o 4 brzegowe piksele, których nie przetwarzamy
	sub $t2, $t2, $s5 # pomniejszona także o padding
	
	#t5 - wskażnik na miejsce w buforze, gdzie wpisujemy nową wartość RGB aktualnie przetwarzanego piksela
	#wpisac zera
	add $t5, $s3, $s7 #analogicznie dla wskaźnika na bufor
	add $t5, $t5, $s7
	addi $t5, $t5, 6
	addi $t5, $t5, -15

	subi $s4, $s4, 4 # przerobimy o cztery wiersze mniej niż wynosi wysokość obrazka
	move $a2, $zero 
petla_po_wierszach_obrazka:
	
	addi $t0, $t0, 12 # przechodząc do nast. wiersza pomijamy 4 piksele brzegowe	
	add $t0, $t0, $s5 # pomijamy też padding
	
	addi $t5, $t5, 12 # analogicznie dla wskaźnika na bufor
	add $t5, $t5, $s5

	move $a3, $zero
petla_po_kolumnach_obrazka:

	addi $t0, $t0, 3 # przechodzimy do następnego piksela obrazka
	addi $t5, $t5, 3 # analogicznie w buforze
		
	# obliczamy t1, chwilowo wykorzystamy t3				 
	add $t3, $s7, $s7 # przesuniemy się o dwa wiersze wstecz, s7 zawiera już padding
	addi $t3, $t3, 6 # i dwie kolumny wstecz
	sub $t1, $t0, $t3 # t1 - wskaznik na piksel odpowiadający pierwszemu (lewy górny róg) okienku maski filtru dla bieżącego piksela
	
	move $a0, $zero	
	move $t6, $zero
	move $t7, $zero
	move $t8, $zero
	move $t3, $zero	# t3 - bieżący wiersz maski filtru

petla_po_wierszach_maski:
	
	move $t4, $zero # t4 - bieżaca kolumna maski filtru

petla_po_kolumnach_maski:
	
	lb $a1, maska_filtru($a0)	
	
	lbu $t9, 0($t1) # kolor Blue
	mul $t9, $t9, $a1
	add $t6, $t6, $t9
		
	lbu $t9, 1($t1) # kolor Green
	mul $t9, $t9, $a1 
	add $t7, $t7, $t9
	
	lbu $t9, 2($t1) # kolor Red
	mul $t9, $t9, $a1 
	add $t8, $t8, $t9	
	
	addi $a0, $a0, 1 # przechodzimy do kolejnego okienka w filtrze
	
	addi $t1, $t1, 3 # przechodzimy do następnej kolumny w masce
	addi $t4, $t4, 1 # zwiększamy licznik kolumn
	blt $t4, rozmiar_maski, petla_po_kolumnach_maski # jeśli przerobiliśmy mniej niż 5 kolumn, to, powrót do pętli po kolumnach maski
	
	# idziemy do kolejnego wiersza maski filtru
	add $t1, $t1, $s7 # przesuwamy się do przodu o jeden wiersz
	subi $t1, $t1, 12 # cofamy się o 4 kolumny
	addi $t3, $t3, 1 # zwiększamy licznik wierszy
	blt $t3, rozmiar_maski, petla_po_wierszach_maski # jeśli przerobiliśmy mniej niż 5 wierszy, to powrót do pętli po wierszach maski

	# przerobiliśmy całą maskę dla bieżącego piksela obrazka
	# dzielimy sumę filtru przez dzielnik
	div $t6, $t6, dzielnik
	div $t7, $t7, dzielnik
	div $t8, $t8, dzielnik

	# normalizacja wartości kolorów RGB do przedziału [0,255]	
kolor_Blue:	
	bge  $t6, 0, normalizacja_Blue
	move $t6, $zero
normalizacja_Blue:
	ble  $t6, 255, kolor_Green
	li $t6, 255	
	
kolor_Green:	
	bge $t7, 0, normalizacja_Green
	move $t7, $zero
normalizacja_Green:
	ble $t7, 255, kolor_Red
	li $t7, 255

kolor_Red:	
	bge $t8, 0, normalizacja_Red
	move $t8, $zero
normalizacja_Red:
	ble $t8, 255, zapisanie_nowego_piksela
	li $t8, 255
	
zapisanie_nowego_piksela:	

	# zapisujemy wartość nowego piksela w buforze
	sb $t6, 0($t5)
	sb $t7, 1($t5)
	sb $t8, 2($t5)
		
	# powrót do pętli po kolumnach obrazka
	addi $a3, $a3, 1 # zwiększamy numer kolumny obrazka o 1
	blt $a3, $t2, petla_po_kolumnach_obrazka
	
	# powrót do pętli po wierszach obrazka
	addi $a2, $a2, 1
	blt $a2, $s4, petla_po_wierszach_obrazka
	
			
####### ZAPISANIE NOWEGO OBRAZKA DO PLIKU ########
	
	li $v0, 13 # otwórz plik wynikowy
	la $a0, output
	li $a1, 1		
	li $a2, 0
	syscall
	move $t9, $v0

	bltz $t9, blad_otwarcia
	
	li $v0, 15 # wpisz nagłówek do pliku wynikowego	
	move $a0, $t9
	la $a1, naglowek
	addi $a2, $zero, 54
	syscall
	
	li $v0, 15 # wpisz piksele		
	move $a0, $t9
	move $a1, $s3
	move  $a2, $s1
	syscall
	
	li $v0, 16 # zamknij plik
	move $a0, $t9
	syscall

koniec:	
	li $v0, 10 # wyjscie z programu
	syscall
			
blad_otwarcia:
	la $a0, blad_otw
	li $v0, 4
	syscall
	b koniec
