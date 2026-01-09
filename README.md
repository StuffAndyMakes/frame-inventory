# frame-inventory Utility

## What It Does

When training ML models with tons of video still frames, this utility makes
it easier to organize and inventory those frames. It was built for the way I
was working with still frames with respect to Apple's Create ML application.

Create ML was looking for images tagged with whatever it was that was in
each image in a directory and it also wanted a JSON file that helped Create
ML to understand what it was looking at.

## Help Output

```shell
% frame-inventory -h
USAGE: frame-inventory [options]

Generates a Create ML JSON manifest from Finder tags on images.

OPTIONS:
  -d <path>         Directory to scan for images (default: current directory).
  -o <filename>     Output JSON filename (default: frames.json).
  -m, --max <int>   Max samples per class.
  -r, --random      Randomize selection when using -m (default: sequential/alphabetical).
  -s, --summary     Print inventory stats only (does not write JSON).
  --copy <path>     Copy the selected images to a destination directory.
  --move <path>     Move the selected images to a destination directory.
  -v, --verbose     Output details about every step and file.
  --dry-run         Simulate execution without modifying files or writing JSON.
  -h, --help        Show this help message.

EXAMPLES:
  frame-inventory -d ./all_images -m 500 --copy ./training_set
  frame-inventory -s
  frame-inventory -d ./images -m 100 --dry-run -v
```

### -d <path>

Set the directory to scan for images. The default is the current directory from
which the command was executed.

### -o <filename>

Set the output JSON filename. The default is "frames.json" if you don't
provide a filename.

### -m <int> or --max <int>

Set the maximum number of images per tag/label. When you have thousands of
images, youi might not need that many, so you can tell the utility to grab
just <int> number of images. You can also ask it to pick random images from
the giant pile you have with the -r switch (see below).

### -r or --random

Make the utility select random images from the files in the directory.
Useful if the files are named by frame number, in order, and you want some
variety in the sample set.

### -s or --summary

Print a summary/stats on only—it does NOT write the JSON inventory file.
(See also --dry-run below.)

### --copy <path>

Copy the selected images to the destination directory you specify in <path>.
Good for organization, you know.

If the destination directory doesn't exist, it will be created.

### --move <path>

Move the selected images to the destination directory you specify in <path>.
Good for organization, you know.

If the destination directory doesn't exist, it will be created.

### -v or --verbose

Output details about every step and file.

### --dry-run

Simulate execution without modifying files or writing the JSON inventory
file.

### -h or --help

Outputs usage information (see above).

