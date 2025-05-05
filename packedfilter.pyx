import struct
import os
import os.path as op
import json
import functools
import numpy as np
import io
import math
import traceback
from libc.stdlib cimport malloc, realloc, free
from libc.string cimport memcpy, strcpy, strlen
from libc.stdint cimport uint64_t, uint32_t, uint8_t

cdef extern from "<ctype.h>":
    int tolower(int c)

ctypedef struct wildcards:
    unsigned char *st 
    uint8_t **wildcard_index

cdef uint64_t xnor(uint64_t t, uint64_t q, unsigned char c):
    return t ^ (q * (c))

cdef uint64_t boolean_reduce(uint64_t x, uint64_t n):
    return (x>>n)&x

cdef union Window:
    uint64_t *i
    unsigned char* c

cdef union B_Window:
    uint64_t *i
    uint8_t *c

cdef int getBitOffset(uint64_t matches):
    cdef int err = -1
    cdef uint64_t value = matches
    if matches & 0xFFFFFFFF00000000:
        value = (value>>32)
        if (value == 1): return 4
        if (value == 256): return 5
        if (value == 65536): return 6
        if (value == 16777216): return 7
    else:
        if (value == 1): return 0
        if (value == 256): return 1
        if (value == 65536): return 2
        if (value == 16777216): return 3
    return err 

cdef unsigned char hexdigit2int(unsigned char xd):
    if int(xd) <= int('9'):
        return int(xd) - int('0')
    xd = tolower(xd)
    if (xd == 'a'): return 10
    if (xd == 'b'): return 11
    if (xd == 'c'): return 12
    if (xd == 'd'): return 13
    if (xd == 'e'): return 14
    if (xd == 'f'): return 15

    return 0

cdef wildcards* decode_hex( unsigned char *st,
                            uint8_t *wildcard_index[100]):
    print(f"Decode_hex: store P locally")
    cdef const unsigned char *src = st
    print(f"Decode_hex: Get text length")
    cdef int text_len = <int>(sizeof(st) / sizeof(unsigned char))
    print(f"Decode_hex: store text locally")
    cdef unsigned char *text = <unsigned char*>malloc(sizeof(unsigned char) * text_len)
    print(f"Decode_hex: Malloc tmp")
    cdef wildcards *tmp = <wildcards*>malloc(sizeof(wildcards))
    print(f"Decode_hex: timp.st = text")
    tmp.st = text
    print(f"Decode_hex: tmp.wildcard_index = wildcard_index")
    tmp.wildcard_index = wildcard_index
    print(f"Decode_hex: init all other vars")
    cdef unsigned char *dst = text
    cdef bint wildcard_sequence_start = 0
    cdef int wildcard_sequence_count = 0
    cdef int wildcard_count = 0
    cdef int count = 0
    cdef int char_count = 0
    cdef int dst_index = 0
    cdef int src_index = 0
    cdef unsigned char high = ' '
    cdef unsigned char low = ' '

    print(f"Decode_hex: Start While loop")
    while src[src_index] != '\0':
        if src[src_index] == '?':      
            print(f"Decode_hex: character is '?'")
            
            wildcard_count += 1
            print(f"Decode_hex: Increase wildcard_count: {wildcard_count}")
            src_index += 2
            print(f"Decode_hex: Increase src_index: {src_index}")
            dst[dst_index] = 0x2A #0x2A -> 42 -> *
            print(f"Decode_hex: Replace and compress all sequential '?' with a single '*'")
            tmp.wildcard_index[wildcard_sequence_count] = &dst[0]
            print(f"Decode_hex: tmp.wildcard_index[wildcard_sequence_count] = &dst[0]")
            wildcard_sequence_start = 1       
            print(f"wildcard_sequence_start = 1")
        else:
            print(f"Decode_hex: character is not wildcard")
            if wildcard_sequence_start == 1:
                print(f"Decode_hex: The last position was a wildcard")
                wildcard_sequence_start = 0
                print(f"Decode_hex: wildcard_sequence_start = 0")
                wildcard_sequence_count += 1
                print(f"Decode_hex: wildcard_sequence_count += 1 : {wildcard_sequence_count}")
                dst_index += 1
                print(f"Decode_hex: dst_index += 1 : {dst_index}")
            src_index += 1
            print(f"Decode_hex: src_index += 1 : {src_index}")
            high = hexdigit2int(src[src_index])
            print(f"Decode_hex: high = hexdigit2int(src[src_index]) : {high}")
            src_index += 1
            print(f"Decode_hex: src_index += 1 : {src_index}")
            low  = hexdigit2int(src[src_index])
            print(f"Decode_hex: low  = hexdigit2int(src[src_index]) : {low}")
            dst[dst_index] = (high << 4) | low
            print(f"Decode_hex: dst[dst_index] = (high << 4) | low : {dst[dst_index]}")
            dst_index += 1
            print(f"Decode_hex: dst_index += 1 : {dst_index}")
        
        char_count += 1
        print(f"Decode_hex: char_count += 1 : {char_count}")
    dst[dst_index] = '\0'
    print(f"Decode_hex: Place string termination char")
    return tmp

def main(filtered_index_dict = None):
    print("PackedFilter Main")
    filtered_index_filename = "filtered_index.json"
    index_filename = "index.txt".encode('UTF-8')
    function_filename = "functions.txt"
    reject_filename = "rejects.txt"
    to_search_filename = 'NMS.exe'.encode('UTF-8')
    patterns_filename = 'patterns.txt'.encode('UTF-8')
    results_filename = "results.json"
    cdef char *output_dir = "output"
    cdef char *input_dir = "input"
    cdef int **results

    path = os.path.dirname(os.path.realpath(__file__))
    encoded_path = path.encode('UTF-8')
    null_term_encoded_path = (encoded_path + b'\0')
    cdef char *dir_path = <char*>malloc(sizeof(char) * len(path))
    strcpy(dir_path, <char*>null_term_encoded_path)

    path = op.join(dir_path, input_dir)
    input_dir = <char*>malloc(sizeof(char) * len(path))
    strcpy(input_dir, path)

    path = op.join(dir_path, output_dir)
    print(path)
    output_dir = <char*>malloc(sizeof(char) * len(path))
    strcpy(output_dir, path)
    binary_data = LoadBinary(input_dir, to_search_filename)
    cdef int **index
    if filtered_index_dict != None:
        index = DictToIndex(filtered_index_dict)
    else:
        print("Checking for filtered index...")
        try:
            with open(op.join(output_dir, filtered_index_filename), "r") as f:
                print(f"Filtered index found at {op.join(output_dir, filtered_index_filename)}")
                print("Extracting filtered index")
                filtered_index_dict = json.load(f)
                index = DictToIndex(filtered_index_dict)
        except Exception as e:
            print(e)
            print("Pdata not found.")
    resultsToReturn = LoadPattern(input_dir, patterns_filename, output_dir, results_filename, binary_data[0], binary_data[1], index)
    #resultsToReturn = {}
    #resultsToReturn = IndexToDict(results)
    return resultsToReturn


cdef IndexToDict(int** results):
    print(f"IndexToDict")
    resultsDict = {}
    cdef int size = sizeof(results) // sizeof(int*)
    cdef int size2 = 0 
    cdef int i = 0
    cdef int j = 0
    for i in range(0, size):
        size2 = sizeof(results[i]) // sizeof(int)
        lst = []
        for j in range(0, size2):
            lst.add(results[i][j])
        resultsDict.add(i, lst)
    return resultsDict

cdef int** DictToIndex(filtered_index_dict):
    print(f"DictToIndex")
    cdef int** results = <int**>malloc(sizeof(int*) * 255)
    filtered_index = []
    for key in filtered_index_dict:
        sizeLst = []
        sizeLst.append(filtered_index_dict[key]["size"])
        sizeLst.extend(list(filtered_index_dict[key]["compliant"]))
        #filtered_index.insert(int(key), sizeLst)
        results[int(key)] = <int*>malloc(sizeof(int) * len(sizeLst))
        for i, thing in enumerate(sizeLst):
            results[int(key)][i] = thing
    return results

cdef (unsigned char*, int) LoadBinary(input_dir, to_search_filename):
    print(f"LoadBinary")
    file_path = op.join(input_dir, <char*>to_search_filename)
    print(f"Load {file_path}.")
    cdef int file_len = os.path.getsize(file_path)
    cdef unsigned char* T = <unsigned char*>malloc(sizeof(unsigned char) * file_len)
    temp_text = bytearray(open(file_path, 'rb').read())
    #null_term_encoded_temp_text = temp_text.encode('UTF-8') + b'\0'
    memcpy(T, <unsigned char*>temp_text, sizeof(unsigned char) * file_len)
    return (T, file_len)

cdef LoadPattern(input_dir, patterns_filename, output_dir, results_filename, T, file_len, int** index):
    print(f"LoadPattern")
    #result[matchCount] = offset   
    #cdef int **result = <int**>malloc(sizeof(int*) sizeof(int) * 255)
    #result[0] = -1
    result = {}
    cdef int pat_count = 0
    cdef uint8_t* P
    cdef uint8_t** wildcard_index
    cdef wildcards *decoded_wildcard
    cdef int* searchResult
    cdef int searchResultCount
    cdef void* byteArrayptr
    cdef object byteArray
    try:
        print(f"LoadPattern: try")   
        print(f"InputDir: {input_dir}")
        print(f"Casted InputDir: {input_dir.decode('utf-8')}")
        print(f"patterns_filename: {patterns_filename}")
        dir = op.join(input_dir, <char*>patterns_filename)
        print(f"Joined: {dir.decode('utf-8')}")
        with open(dir, 'r') as pat_file:
            print(f"Pattern file found at {op.join(input_dir, patterns_filename)}. Checking patterns.")
            #has the format (pattern, binary)
            #pat_list = str(pat_file.read()).split(",")      
            pat_list = [line.rstrip('\n') for line in pat_file]     
            pat_count = 0
            for pat in pat_list:
                hex_string = pat.replace(" ", "")
                print(f"LoadPattern: replaced hex_string = {hex_string}")
                patt_len = len(hex_string)
                print(f"LoadPattern: patt_len = {patt_len}")
                P = <uint8_t*>malloc(sizeof(uint8_t) * patt_len)
                print(f"LoadPattern: P malloced")
                #byteArray = <uint8_t*>malloc(sizeof(uint8_t) * patt_len)
                byteArray = bytearray(hex_string.encode('utf-8'))
                print(f"LoadPattern: byteArray stored : {byteArray}")
                byteArrayptr = <void*> byteArray
                print(f"LoadPattern: byteArray cast to void*")
                memcpy(P, byteArrayptr, <size_t>patt_len)
                print(f"LoadPattern: byteArray memcpy into P")
                wildcard_index = <uint8_t**>malloc(sizeof(uint8_t*) * 100)
                print(f"LoadPattern: wildcard_index malloced")
                decoded_wildcard = decode_hex(P, wildcard_index)
                print(f"LoadPattern: Decode wildcard : {decoded_wildcard.st}")
                P = decoded_wildcard.st
                print(f"LoadPattern: Set P as Decoded wildcard")
                wildcard_index = decoded_wildcard.wildcard_index
                print(f"LoadPattern: Set wildcard_index")
                searchResult = index_search(P, patt_len, T, file_len, wildcard_index, index)
                #result[pat_count] = <int*>
                searchResultCount = <int>(sizeof(searchResult)/ sizeof(int))
                searchResultLst = []
                for i in range(0,searchResultCount):
                    searchResultLst.insert(i, searchResult[i])
                result.update({pat: searchResultLst})
                pat_count += 1
    except Exception as e:
        print(f"Error: {e}")
        print(f"Unable to open {op.join(input_dir,patterns_filename)}")
    json.dump(result,open(op.join(output_dir, results_filename), 'w'))
    return result

cdef int* index_search( unsigned char *query_array,
                        int query_len,
                        unsigned char* text, 
                        int text_len,
                        uint8_t* wildcard_index[100],
                        int* file_index[256]):
    print(f"index_search")                    
    #Setup
    print(f"index_search: Setup ints")
    cdef int byte_offset = 0
    cdef int count = 0
    cdef int wildcard_count = 0
    cdef int first_offset = 0
    print(f"index_search: First char = {query_array}")
    cdef uint8_t* first_byte = &query_array[0]
    cdef int byte_index_size = file_index[first_byte[0]][0]
    print(f"index_search: Stored byte_index_size = {file_index[first_byte[0]][0]}")
    cdef int results[255]
    print(f"index_search: Setup int*")
    cdef int* byte_index = file_index[first_byte[0]]
    byte_index_size = sizeof(file_index[first_byte[0]]) / sizeof(int)
    print(f"index_search: Calculated byte_index_size = {sizeof(byte_index) / sizeof(int)}")
    print(f"index_search: Setup uint8_t*")
    cdef uint8_t* byte_ptr = &query_array[0]
    cdef uint8_t* last_byte = &query_array[query_len-1]
    
    cdef uint8_t* match_start

    cdef uint8_t* jump = wildcard_index[wildcard_count]
    print(f"index_search: Setup uint64_t")
    cdef uint64_t query_matches = 0x101010101010101UL
    cdef uint64_t value = 0
    cdef uint64_t value2 = 0
    cdef uint64_t value3 = 0
    cdef uint64_t reduced_value = 0
    print(f"index_search: Setup text_window")
    cdef Window* text_window = <Window*>malloc(sizeof(Window))
    print(f"index_search: Setup file_window")
    cdef B_Window* file_window = <B_Window*>malloc(sizeof(B_Window))

    #for each location in the associated byte_index, search until a match or mismatch is found. repeat until all locaitons are checked
    cdef int i = 1
    cdef int t = 0
    try:
        for i in range(1,byte_index_size):
            print(f"index_search: for (i){i} in range({byte_index_size})")
            byte_offset = byte_index[i]
            print(f"index_search: byte_offset = byte_index[{i}] : {byte_offset} of {text_len}")
            file_window.c = &text[byte_offset]
            print(f"index_search: file_window.c = &text[{byte_offset}] : {file_window.c}")
            print(f"index_search: Init local vars")
            query_matches = 0x101010101010101UL
            value = 0
            value2 = 0
            value3 = 0
            reduced_value = 0

            byte_ptr = first_byte
            print(f"index_search: byte_ptr = first_byte")
            wildcard_count = 0
            print(f"index_search: for t in range ({query_len})")
            #while (&text_window.c[0] < &text[text_len-1]):
            for t in range (query_len):
                print(f"index_search: for (t){t} in range({query_len})")
                if &text_window.c[0] > &text[text_len-1]:
                    print(f"index_search: (&text_window.c[0]){&text_window.c[0]} > (&text[text_len-1]){&text[text_len-1]}")
                    print(f"index_search: break")
                    break;
                #if the current byte_ptr is a wildcard segment skip that segment. check if wildcard is the last char in pattern
                if &byte_ptr[0] == jump:
                    print(f"index_search: encountered jump")
                    if (&file_window.c[0] > &text[text_len-1]) == False:
                        print(f"index_search: ({&file_window.c[0] } > {&text[text_len-1])} == False") 
                        byte_ptr += (int)*jump
                        print(f"index_search: byte_ptr += (int)*jump") 
                        file_window.c += (int)*jump
                        print(f"index_search: file_window.c += (int)*jump") 
                        wildcard_count += 1
                        print(f"index_search: wildcard_count += 1") 
                        jump = wildcard_index[wildcard_count]
                        print(f"index_search: jump = wildcard_index[wildcard_count]") 
                        if &byte_ptr[0] != last_byte:
                            print(f"index_search: &byte_ptr[0] != last_byte") 
                            if (count < 256) == True:
                                print(f"index_search: count < 256 == True") 
                                results[count] = (int)(match_start + first_offset)
                                print(f"index_search: results[count] = (int)(match_start + first_offset)") 
                                count += 1
                                print(f"index_search: count += 1") 
                            break
                    else:
                        break
                else:
                    print(f"index_search: Evaluate bytes")
                    value = ~xnor(file_window.i[0], query_matches, byte_ptr[0])   
                    print(f"index_search: value = ~xnor(file_window.i[0], query_matches, byte_ptr[0])") 
                    value2 = boolean_reduce(value, 4)
                    print(f"index_search: value2 = boolean_reduce(value, 4)") 
                    value3 = boolean_reduce(value2, 2)
                    print(f"index_search: value3 = boolean_reduce(value2, 2)") 
                    reduced_value = boolean_reduce(value3, 1)
                    print(f"index_search: reduced_value = boolean_reduce(value3, 1)") 
                    query_matches = reduced_value & query_matches
                    print(f"index_search: query_matches = reduced_value & query_matches") 

                    if query_matches > 0:
                        print(f"index_search: query_matches > 0") 
                        if &byte_ptr[0] == last_byte:
                            print(f"index_search: pattern matched") 
                            print(f"index_search: &byte_ptr[0] == last_byte") 
                            if count < 256:
                                print(f"index_search: count < 256") 
                                results[count] = (int)(match_start + getBitOffset(first_offset))
                                print(f"index_search: results[count] = (int)(match_start + getBitOffset(first_offset))") 
                                count += 1
                                print(f"index_search: count += 1") 
                            break
                        else:
                            print(f"index_search: pattern match in process") 
                            if &byte_ptr[0] == first_byte:
                                print(f"index_search: &byte_ptr[0] == first_byte") 
                                match_start = file_window.c 
                                print(f"index_search: match_start = file_window.c ") 
                                first_offset = query_matches
                                print(f"index_search: first_offset = query_matches") 
                            byte_ptr += 1
                            print(f"index_search: byte_ptr += 1") 
                            file_window.c += 1
                            print(f"index_search: file_window.c += 1") 
                    else:
                        print(f"index_search: pattern mismatch, go to next location") 
                        break
    except Exception as e:
        print(f"Error: {e}")
    print(f"index_search: finished, return results") 
    return results