import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const [sourceFile, destinationDirectory] = process.argv.slice(2);
if (!sourceFile || !destinationDirectory) {
  throw new Error('Usage: node extract-zenith-docs.mjs <compiled-chunk> <destination-directory>');
}

const source = fs.readFileSync(sourceFile, 'utf8');

function extractArray(name) {
  const marker = `const ${name} = [`;
  const markerIndex = source.indexOf(marker);
  if (markerIndex < 0) {
    throw new Error(`Could not locate ${name}`);
  }

  const start = source.indexOf('[', markerIndex);
  let depth = 0;
  let quote = '';
  let escaped = false;

  for (let index = start; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === quote) {
        quote = '';
      }
      continue;
    }

    if (character === '"' || character === "'" || character === '`') {
      quote = character;
      continue;
    }

    if (character === '[') {
      depth += 1;
    } else if (character === ']') {
      depth -= 1;
      if (depth === 0) {
        return vm.runInNewContext(`(${source.slice(start, index + 1)})`, Object.create(null));
      }
    }
  }

  throw new Error(`Could not find the end of ${name}`);
}

fs.mkdirSync(destinationDirectory, { recursive: true });
fs.writeFileSync(
  path.join(destinationDirectory, 'help-articles.json'),
  JSON.stringify(extractArray('tt'), null, 2),
  'utf8'
);
fs.writeFileSync(
  path.join(destinationDirectory, 'function-documentation.json'),
  JSON.stringify(extractArray('Ht'), null, 2),
  'utf8'
);
