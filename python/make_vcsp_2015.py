"""
Generates a library ready to be used as a VCSP endpoint for content library 2016 (vsphere 6.5).
"""

__author__ = 'VMware, Inc.'
__copyright__ = 'Copyright VMware, Inc. All rights reserved.'

import hashlib
import logging
import json
import os
import uuid
import sys

from datetime import datetime

VCSP_VERSION = 2
ISO_FORMAT = "%Y-%m-%dT%H:%MZ"
FORMAT = "json"
LIB_FILE = ''.join(("lib", os.extsep, FORMAT))
ITEMS_FILE = ''.join(("items", os.extsep, FORMAT))
ITEM_FILE = ''.join(("item", os.extsep, FORMAT))

logger = logging.getLogger(__name__)

def _md5_for_file(f, md5=None, block_size=2**20):
    if md5 is None:
        md5 = hashlib.md5()
    while True:
        data = f.read(block_size)
        if not data:
            break
        md5.update(data)
    return md5


def _md5_for_folder(folder):
    md5 = None
    for files in os.listdir(folder):
        if ITEM_FILE not in files:
            with open(os.path.join(folder, files), "rb") as handle:
                md5 = _md5_for_file(handle, md5)
    return md5.hexdigest()


def _make_lib(name, id=uuid.uuid4(), creation=datetime.now(), version=1):
    return {
            "vcspVersion": str(VCSP_VERSION),
            "version": str(version),
            "contentVersion": "1",
            "name": name,
            "id": "urn:uuid:%s" % id,
            "created": creation.strftime(ISO_FORMAT),
            "capabilities": {
            "transferIn": [ "httpGet" ],
            "transferOut": [ "httpGet" ],
            },
        "itemsHref": ITEMS_FILE
    }


def _make_item(directory, vcsp_type, name, files, description="", properties={},
               identifier=uuid.uuid4(), creation=datetime.now(), version=2):
    return {
        "created": creation.strftime(ISO_FORMAT),
        "description": description,
        "version": str(version),
        "files": files,
        "id": "urn:uuid:%s" % identifier,
        "name": name,
        "properties": properties,
        "selfHref": "%s/%s" % (directory, ITEM_FILE),
        "type": vcsp_type
    }


def _make_items(items, version=1):
    return {
        "items": items
    }


def _dir2item(path, directory, md5_enabled):
    files_items = []
    name = os.path.split(path)[-1]
    vcsp_type = "vcsp.file"
    folder = ""
    folder_md5 = ""
    for f in os.listdir(path):
        if f == ".DS_Store" or f == ''.join((directory, os.extsep, FORMAT)):
            continue
        else:
            if f == "item.json":
                continue # skip the item.json meta data files
            p = os.path.join(path, f)
            m = hashlib.md5()
            new_folder = os.path.dirname(p)
            if new_folder != folder: # new folder (ex: template1/)
                if md5_enabled:
                    folder_md5 = _md5_for_folder(new_folder)
                folder = new_folder
            if md5_enabled:
                m.update(os.path.dirname(p).encode('utf-8'))
            if ".ovf" in p:
                vcsp_type = "vcsp.ovf"
            elif ".iso" in p:
                vcsp_type = "vcsp.iso"
            size = os.path.getsize(p)
            href = "%s/%s" % (directory, f)
            h = ""
            if md5_enabled:
                with open(p, "rb") as handle:
                    h = _md5_for_file(handle)
            files_items.append({
                "name": f,
                "size": size,
                "etag": folder_md5,
                "hrefs": [ href ]
            })
    return _make_item(name, vcsp_type, name, files_items, identifier = uuid.uuid4())


def make_vcsp(lib_name, lib_path, md5_enabled):
    lib_json_loc = os.path.join(lib_path, LIB_FILE)
    lib_items_json_loc = os.path.join(lib_path, ITEMS_FILE)

    lib_id = uuid.uuid4()
    lib_create = datetime.now()
    lib_version = 1
    updating_lib = False
    if os.path.isfile(lib_json_loc):
        logger.info("%s already exists (%s)" % (LIB_FILE, lib_json_loc))
        try:
            with open(lib_json_loc, "r") as f:
                old_lib = json.load(f)
            if "id" in old_lib:
                lib_id = old_lib["id"].split(":")[-1]
            if "created" in old_lib:
                lib_create = datetime.strptime(old_lib["created"], ISO_FORMAT)
            if "version" in old_lib:
                lib_version = old_lib["version"]
                updating_lib = True
        except:
            logger.error("Failed to read %s" % lib_json_loc)
            pass

    old_items = {}
    if os.path.isfile(lib_items_json_loc):
        logger.info("%s already exists (%s)" % (ITEMS_FILE, lib_items_json_loc))
        try:
            with open(lib_items_json_loc, "r") as f:
                old_data = json.load(f)
            for item in old_data["items"]:
                old_items[item["name"]] = item
        except:
            logger.error("Failed to read %s" % lib_items_json_loc)
            pass

    items = []
    changed = False
    for item_path in os.listdir(lib_path):
        p = os.path.join(lib_path, item_path)
        if not os.path.isdir(p):
            continue  # not interesting
        items_json = _dir2item(p, item_path, md5_enabled)
        if item_path not in old_items and updating_lib:
            changed = True
        elif item_path in old_items:
            file_changed = False
            items_json["id"] = old_items[item_path]["id"]
            items_json["created"] = old_items[item_path]["created"]
            items_json["version"] = old_items[item_path]["version"]
            file_names = set([i["name"] for i in items_json["files"]])
            old_file_names = set([i["name"] for i in old_items[item_path]["files"]])
            if file_names != old_file_names:
                # files added or removed
                changed = True
                file_changed = True
            for f in items_json["files"]:
                if file_changed:
                    break
                for old_f in old_items[item_path]["files"]:
                    if f["name"] == old_f["name"] and f["etag"] != old_f["etag"]:
                        changed = True
                        file_changed = True
                        break
            if file_changed:
                item_version = int(items_json["version"])
                items_json["version"] = str(item_version + 1)
            del old_items[item_path]
        json_item_file = ''.join((p, os.sep, ITEM_FILE))
        with open(json_item_file, "w") as f:
            json.dump(items_json, f, indent=2)
        items.append(items_json)

    if updating_lib and len(old_items) != 0:
        changed = True  # items were removed

    if updating_lib and not changed:
        logger.info("Nothing to update, quitting")
        return
    if changed:
        lib_version = int(lib_version)
        lib_version += 1
    logger.info("Saving results to %s and %s" % (lib_json_loc, lib_items_json_loc))
    with open(lib_json_loc, "w") as f:
        json.dump(_make_lib(lib_name, lib_id, lib_create, lib_version), f, indent=2)

    with open(lib_items_json_loc, "w") as f:
        json.dump(_make_items(items, lib_version), f, indent=2)

def main():
    if len(sys.argv) < 3:
        print ("Usage: python %s <library name> <library location"
               " on disk> <md5check, default true>" % sys.argv[0])
        sys.exit()

    lib_name = sys.argv[1]
    lib_path = sys.argv[2]
    md5_enabled = True
    if len(sys.argv) == 4:
       md5_enabled = (sys.argv[3].lower() == 'true')

    make_vcsp(lib_name,lib_path, md5_enabled)

if __name__ == "__main__":
    main()
