import re
from lxml import etree
from lxml.etree import QName
import xml.etree.ElementTree as ET
import sys
import datetime


# function which creates the new empty output file xml
def generate_xml(fileName):
    # create the root and add the attributes
    root = etree.XML('<TEI></TEI>')
    root.attrib[QName("http://www.w3.org/XML/1998/namespace", "space")] = "preserve"
    root.attrib[QName("http://www.w3.org/XML/1998/namespace", "xmlns")] = "http://www.tei-c.org/ns/1.0"
    root.attrib[QName("http://www.w3.org/XML/1998/namespace", "lang")] = "eng"
    tree = ET.ElementTree(root)
    # add the text element
    text_node = etree.SubElement(root, 'text')
    etree.SubElement(text_node, 'listBibl')
    # try-except commentato solo per non riscrivere il file tutte le volte
    try:
        # create and write the new file
        with open(fileName, 'wb') as files:
            tree.write(files, encoding='utf-8', xml_declaration=True)
    except:
        # couldn't create a new file
        print('Ops, something went wrong. Could not create the file ', fileName)
        sys.exit(1)


# function which writes the output file xml with teh tree created in the specific functions
def add_to_xml(tree, filename):
    pprinted_xml = etree.tostring(tree, encoding='UTF-8', xml_declaration=True, pretty_print=True)
    # print(pprinted_xml)
    with open(filename, 'wb') as files:
        files.write(pprinted_xml)


# function which cleans the dates from the references and sets them in order yy-mm-dd
def get_time(date):
    if " " in date:
        splitter = " "
    elif "-" in date:
        splitter = "-"
    else:
        date = re.sub('\D', '', date)
        try:
            datetime.datetime.strptime(date, "%Y")
            return date
        except ValueError:
            print('Not able to match the year.')
            return ""
    #  da qua in poi tentare un for loop per fare il match della data con un solo try/ else per caso
    if len(splitter) != 0:
        split_date = date.split(splitter)
        try:
            if len(split_date) == 2:
                if not split_date[0].isdigit():
                    try:
                        new_date = datetime.datetime.strptime(date, '%B'+splitter+'%Y')  # month full year full
                    except ValueError:
                        new_date = datetime.datetime.strptime(date, '%b'+splitter+'%Y')  # month partial year full
                else:
                    if split_date[1].isdigit():
                        try:
                            new_date = datetime.datetime.strptime(date, '%m'+splitter+'%Y')  # month digit year full
                        except ValueError:
                            new_date = datetime.datetime.strptime(date, '%Y'+splitter+'%m')  # month digit year full
                    else:
                        try:
                            new_date = datetime.datetime.strptime(date, '%Y'+splitter+'%b')  # year full month partial
                        except ValueError:
                            new_date = datetime.datetime.strptime(date, '%Y'+splitter+'%B')  # year full month full

                # print(new_date.strftime('%Y-%m'))
                return new_date.strftime('%Y-%m')

            else:
                if not split_date[1].isdigit():
                    if int(split_date[2]) >= 31:
                        try:
                            new_date = datetime.datetime.strptime(date, '%d'+splitter+'%B'+splitter+'%Y')  # day month full year full
                        except ValueError:
                            new_date = datetime.datetime.strptime(date, '%d'+splitter+'%b'+splitter+'%Y')  # day month partial year full
                    else:
                        try:
                            new_date = datetime.datetime.strptime(date, '%Y'+splitter+'%B'+splitter+'%d')  # year full month full day
                        except ValueError:
                            new_date = datetime.datetime.strptime(date, '%Y'+splitter+'%b'+splitter+'%d')  #  year full month partial day
                else:
                    if split_date[0].isdigit() and len(split_date[2]) == 4:
                        try:
                            new_date = datetime.datetime.strptime(date, '%d'+splitter+'%m'+splitter+'%Y')  # month digit day year full
                        except ValueError:
                            new_date = datetime.datetime.strptime(date, '%m'+splitter+'%d'+splitter+'%Y')  # day month digit year full
                    elif split_date[0].isdigit() and len(split_date[0]) == 4:
                        try:
                            new_date = datetime.datetime.strptime(date, '%Y'+splitter+'%m'+splitter+'%d')  # year full month digit day
                        except:
                            new_date = datetime.datetime.strptime(date, '%Y'+splitter+'%d'+splitter+'%m')  # year full day month digit

                    else:
                        try:
                            new_date = datetime.datetime.strptime(date, '%B'+splitter+'%d'+splitter+'%Y')  # month full day year full
                        except ValueError:
                            new_date = datetime.datetime.strptime(date, '%b'+splitter+'%d'+splitter+'%Y')  # month partial day year full

            # print(new_date.strftime('%Y-%m-%d'))
            return new_date.strftime('%Y-%m-%d')

        except ValueError:
            return ""



# get_time("1996-12-05")
