import time
import lgpio
import socket
import json
import datetime

class DHT22MissingDataError(Exception):
    pass


class DHT22CRCError(Exception):
    pass


class DHT22:
    'DHT22 sensor reader class for Raspberry Pi using lgpio'

    def __init__(self, gpio):
        self.__gpio = gpio
        self.__h = lgpio.gpiochip_open(0) 

    def read(self):

        lgpio.gpio_claim_output(self.__h, self.__gpio)

        self.__send_and_sleep(1, 0.58)  

        self.__send_and_sleep(0, 0.02)

        lgpio.gpio_claim_input(self.__h, self.__gpio, lgpio.SET_PULL_UP)

        data = self.__collect_input()

        pull_up_lengths = self.__parse_data_pull_up_lengths(data)

        if len(pull_up_lengths) != 40:
            raise DHT22MissingDataError

        bits = self.__calculate_bits(pull_up_lengths)

        the_bytes = self.__bits_to_bytes(bits)

        checksum = self.__calculate_checksum(the_bytes)
        if the_bytes[4] != checksum:
            raise DHT22CRCError

        humidity_raw = (the_bytes[0] << 8) + the_bytes[1]
        humidity = float(humidity_raw) / 10.0

        temp_raw = (the_bytes[2] << 8) + the_bytes[3]

        if (temp_raw & 0x8000) != 0:
            temperature = - float(temp_raw & 0x7FFF) / 10.0
        else:
            temperature = float(temp_raw) / 10.0

        return temperature, humidity, checksum
        
    def __send_and_sleep(self, output, sleep):
        lgpio.gpio_write(self.__h, self.__gpio, output)
        time.sleep(sleep)


    def __collect_input(self):
        unchanged_count = 0
        max_unchanged_count = 100

        last = -1
        data = []
        while True:
            current = lgpio.gpio_read(self.__h, self.__gpio)
            data.append(current)
            if last != current:
                unchanged_count = 0
                last = current
            else:
                unchanged_count += 1
                if unchanged_count > max_unchanged_count:
                    break

        return data
    
    def __parse_data_pull_up_lengths(self, data):
        STATE_INIT_PULL_DOWN = 1
        STATE_INIT_PULL_UP = 2
        STATE_DATA_FIRST_PULL_DOWN = 3
        STATE_DATA_PULL_UP = 4
        STATE_DATA_PULL_DOWN = 5

        state = STATE_INIT_PULL_DOWN

        lengths = []
        current_length = 0 

        for i in range(len(data)):

            current = data[i]
            current_length += 1

            if state == STATE_INIT_PULL_DOWN:
                if current == 0:
                    state = STATE_INIT_PULL_UP
                    continue
                else:
                    continue
            if state == STATE_INIT_PULL_UP:
                if current == 1:
                    state = STATE_DATA_FIRST_PULL_DOWN
                    continue
                else:
                    continue
            if state == STATE_DATA_FIRST_PULL_DOWN:
                if current == 0:
                    state = STATE_DATA_PULL_UP
                    continue
                else:
                    continue
            if state == STATE_DATA_PULL_UP:
                if current == 1:
                    current_length = 0
                    state = STATE_DATA_PULL_DOWN
                    continue
                else:
                    continue
            if state == STATE_DATA_PULL_DOWN:
                if current == 0:
                    lengths.append(current_length)
                    state = STATE_DATA_PULL_UP
                    continue
                else:
                    continue

        return lengths

    def __calculate_bits(self, pull_up_lengths):
        # find shortest and longest period
        shortest_pull_up = 1000
        longest_pull_up = 0

        for i in range(0, len(pull_up_lengths)):
            length = pull_up_lengths[i]
            if length < shortest_pull_up:
                shortest_pull_up = length
            if length > longest_pull_up:
                longest_pull_up = length

        halfway = shortest_pull_up + (longest_pull_up - shortest_pull_up) / 2
        bits = []

        for i in range(0, len(pull_up_lengths)):
            bit = False
            if pull_up_lengths[i] > halfway:
                bit = True
            bits.append(bit)

        return bits
    
    def __bits_to_bytes(self, bit_list0):
        bytes = []
        length = len(bit_list0)
        byte_d = 0

        for i in range(0, length):
            byte_d = byte_d << 1
            
            if (1 == bit_list0[i]):
                byte_d = byte_d | 1
            else:
                byte_d = byte_d | 0

            if ((i + 1) % 8 == 0):
                bytes.append(byte_d)
                byte_d = 0

        return bytes

    def __calculate_checksum(self, bytes0):
        checksum = (bytes0[0] & 0xff) + (bytes0[1] & 0xff) + (bytes0[2] & 0xff) + (bytes0[3] & 0xff)
        return checksum & 0xFF
    
    def close(self):
        lgpio.gpiochip_close(self.__h)  
 
SERVER_IP = "10.192.137.117"
PORT = 8765

if __name__ == '__main__':
    import datetime
    dht22_instance = DHT22(gpio=26)
    print("DHT22 sensor initialized on GPIO26.")

    try:
         count = 0
         while True:
            try:
                tempe, hum, check = dht22_instance.read()
                print("Last valid input: " + str(datetime.datetime.now()))
                print("Temperature: %-3.1f C" % tempe)
                print("Humidity: %-3.1f %%" % hum)
                data = {
                    "time":str(datetime.datetime.now()),
                    "temperature":tempe,
                    "humidity":hum
                }
                json_data = json.dumps(data)
                sock = socket.socket(
                    socket.AF_INET,                    
                    socket.SOCK_STREAM
                )
                print("data")
                sock.connect((SERVER_IP, PORT))
                sock.send(json_data.encode("utf-8"))
                sock.close()
                print("send data")
                count += 1
                
            except DHT22CRCError:
                print('DHT22CRCError: ' + str(datetime.datetime.now()))
            except DHT22MissingDataError:
                print('DHT22MissingDataError: '+ str(datetime.datetime.now()))
            time.sleep(3)
            
        

    except KeyboardInterrupt:
        print('Ctrl-C is pressed.')
        print('Closing DHT22 instance.')
        dht22_instance.close()

