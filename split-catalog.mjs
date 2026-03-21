import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

const base = '/Users/shayco/ClaudPeer/ClaudPeer/Resources/Catalog';

// --- Agents ---
const agents = JSON.parse(readFileSync(join(base, 'AgentCatalog.json'), 'utf8'));
const agentIds = agents.map(a => a.catalogId);
writeFileSync(join(base, 'agents', 'index.json'), JSON.stringify(agentIds, null, 2) + '\n');
for (const agent of agents) {
  writeFileSync(join(base, 'agents', `${agent.catalogId}.json`), JSON.stringify(agent, null, 2) + '\n');
}
console.log(`Wrote ${agents.length} agent files`);

// --- MCPs ---
const mcps = JSON.parse(readFileSync(join(base, 'MCPCatalog.json'), 'utf8'));
const mcpIds = mcps.map(m => m.catalogId);
writeFileSync(join(base, 'mcps', 'index.json'), JSON.stringify(mcpIds, null, 2) + '\n');
for (const mcp of mcps) {
  writeFileSync(join(base, 'mcps', `${mcp.catalogId}.json`), JSON.stringify(mcp, null, 2) + '\n');
}
console.log(`Wrote ${mcps.length} MCP files`);

// --- Skills (metadata only, content removed from JSON) ---
const skills = JSON.parse(readFileSync(join(base, 'SkillCatalog.json'), 'utf8'));
const skillIds = skills.map(s => s.catalogId);
writeFileSync(join(base, 'skills', 'index.json'), JSON.stringify(skillIds, null, 2) + '\n');
for (const skill of skills) {
  const { content, ...meta } = skill;
  writeFileSync(join(base, 'skills', `${skill.catalogId}.json`), JSON.stringify(meta, null, 2) + '\n');
}
console.log(`Wrote ${skills.length} skill metadata files`);
console.log('Done splitting catalogs');
