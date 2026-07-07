import asyncio

import discord

from xlr_bot_core import xlr_embed


class CaptchaView(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label="Verify", style=discord.ButtonStyle.success, custom_id="xlr_verify_captcha")
    async def verify(self, interaction: discord.Interaction, button: discord.ui.Button):
        conf = interaction.client.store.get(interaction.guild.id, "captcha")
        if not conf:
            await interaction.response.send_message("Verification is not configured.", ephemeral=True)
            return
        role = interaction.guild.get_role(int(conf["role"]))
        if not role:
            await interaction.response.send_message("The verification role no longer exists.", ephemeral=True)
            return
        if role in interaction.user.roles:
            await interaction.response.send_message("You are already verified.", ephemeral=True)
            return
        try:
            await interaction.user.add_roles(role, reason="Captcha verification")
        except discord.HTTPException:
            await interaction.response.send_message("I could not assign the verification role.", ephemeral=True)
            return
        await interaction.response.send_message(f"You have been verified and received **{role.name}**.", ephemeral=True)


class TicketPanelView(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label="Create Ticket", style=discord.ButtonStyle.success, emoji="📩", custom_id="xlr_create_ticket")
    async def create_ticket(self, interaction: discord.Interaction, button: discord.ui.Button):
        await interaction.response.defer(ephemeral=True)
        guild = interaction.guild
        category = discord.utils.get(guild.categories, name="Tickets")
        if not category:
            category = await guild.create_category("Tickets")
        support_role = discord.utils.get(guild.roles, name="Support Team")
        overwrites = {
            guild.default_role: discord.PermissionOverwrite(view_channel=False),
            interaction.user: discord.PermissionOverwrite(view_channel=True, send_messages=True),
            guild.me: discord.PermissionOverwrite(view_channel=True, send_messages=True),
        }
        if support_role:
            overwrites[support_role] = discord.PermissionOverwrite(view_channel=True, send_messages=True)
        channel = await guild.create_text_channel(
            f"ticket-{interaction.user.name}"[:32],
            category=category,
            overwrites=overwrites,
        )
        embed = xlr_embed(
            interaction.client,
            title=f"Ticket for {interaction.user.display_name}",
            description="Please describe your issue and a staff member will assist you shortly.",
        )
        mention = support_role.mention if support_role else ""
        await channel.send(content=f"{interaction.user.mention} {mention}", embed=embed, view=CloseTicketView())
        await interaction.followup.send(f"Your ticket has been created: {channel.mention}", ephemeral=True)


class CloseTicketView(discord.ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label="Close Ticket", style=discord.ButtonStyle.danger, emoji="🔒", custom_id="xlr_close_ticket")
    async def close_ticket(self, interaction: discord.Interaction, button: discord.ui.Button):
        await interaction.response.send_message("Closing this ticket in 5 seconds...", ephemeral=True)
        await asyncio.sleep(5)
        try:
            await interaction.channel.delete(reason="Ticket closed")
        except discord.HTTPException:
            pass
