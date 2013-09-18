Jason Wilkin
1/11/13
Dostunes
========

Dostunes is a music player written in assembly language. It reads a .txt file of notes and beats, turning the speaker on and off and playing the approprate frequencies.

Example dostunes file:

    60

    En4
    4
    Gn4
    4
    rr0
    4
    Fn4
    4

    

The first line of the file is the BPM (Beats Per Minute) for the tune. It is then followed by a newline character and then each note and beat on its own line. A note line must have the format of: note, natural/flat/sharp, octave (En7 or A#4). Natural/flat/sharp is represented by the n/b/# characters. A beat line will always follow a note line. Each beat line represents the number of beats the preceding note will be played for.

A rest will always look like rr0 on a note line and can be played for any number of beats.

The file must always be terminated by a single newline character.
