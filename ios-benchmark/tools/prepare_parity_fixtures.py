"""Prepare deterministic Python RGB fixtures for Swift cross-decoder checks."""
import hashlib
from pathlib import Path
import struct
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT))
from benchmark.candidates import dct_registered as d
from benchmark import harness as h


def raw(path,image):
    path.write_bytes(struct.pack('>II',*image.size)+image.convert('RGB').tobytes())


def main():
    out=ROOT/'benchmark/runs/native-parity-v1';out.mkdir(parents=True,exist_ok=True)
    y,x=np.mgrid[:384,:512]
    images=[Image.fromarray(np.stack([x%256,y%256,(x+y)%256],axis=-1).astype('uint8')),
            Image.fromarray(np.random.default_rng(26).integers(20,236,(384,512,3),dtype=np.uint8))]
    first=h.jsonl(ROOT/'benchmark/manifests/openimages-starter.jsonl')[0]
    images.append(h.load_normalized(h.safe_media_path(first['path'])))
    jobs=[]
    for i,image in enumerate(images):
        identifier=hashlib.sha256(f'parity-fixture-{i}'.encode()).hexdigest()[:32]
        marked=d.embed(image,identifier);raw(out/f'fixture{i}.rgb',image);raw(out/f'fixture{i}-python.rgb',marked)
        jobs.append(f'fixture{i}\t{identifier}')
    (out/'jobs.tsv').write_text('\n'.join(jobs)+'\n')


if __name__=='__main__': main()
